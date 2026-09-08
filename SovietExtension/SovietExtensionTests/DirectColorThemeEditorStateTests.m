#import <XCTest/XCTest.h>
#import "DirectColorTheme.h"
#import "DirectColorThemeEditorState.h"

@interface DirectColorThemeEditorStateTests : XCTestCase
@end

@implementation DirectColorThemeEditorStateTests

- (NSDictionary *)colorsWithSeed:(NSUInteger)seed {
    NSArray *keys = @[@"base", @"sidebar", @"ribbon", @"outgoing_bubble", @"incoming_bubble",
                      @"text", @"subtext", @"accent", @"link", @"danger"];
    NSMutableDictionary *colors = [NSMutableDictionary dictionary];
    [keys enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop) {
        colors[key] = [NSString stringWithFormat:@"#%06lX", (unsigned long)(seed + idx) & 0xFFFFFF];
    }];
    return colors;
}

- (DirectColorTheme *)themeNamed:(NSString *)name identifier:(NSString *)identifier {
    NSDictionary *document = @{@"schema_version":@1, @"id":identifier, @"name":name, @"source":@"custom",
        @"created_at":@"2024-01-01T00:00:00Z", @"updated_at":@"2024-01-01T00:00:00Z",
        @"light":[self colorsWithSeed:0x101010], @"dark":[self colorsWithSeed:0x202020],
        @"advanced":@{@"light":@{@"raw_light":@"#ABCDEF"}, @"dark":@{}}};
    return [DirectColorTheme themeFromDictionary:document error:nil];
}

- (void)testBuiltinSelectionDeepCopiesTenColorsAndIsReadOnly {
    NSMutableDictionary *presets = [[DirectColorThemeEditorState builtInPresets] mutableCopy];
    NSMutableDictionary *catppuccin = [presets[@"catppuccin"] mutableCopy];
    NSMutableDictionary *sourceLight = [catppuccin[@"light"] mutableCopy];
    catppuccin[@"light"] = sourceLight; presets[@"catppuccin"] = catppuccin;
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:presets customThemes:@[]];
    sourceLight[@"base"] = @"#000000";
    XCTAssertTrue([state selectIdentifier:@"builtin:catppuccin"]);
    XCTAssertTrue(state.isBuiltIn);
    XCTAssertEqual(state.lightColors.count, 10u);
    XCTAssertEqual(state.darkColors.count, 10u);
    XCTAssertEqualObjects([NSSet setWithArray:state.lightColors.allKeys], DirectColorTheme.requiredColorKeys);
    XCTAssertEqualObjects(state.lightColors[@"base"], @"#EFF1F5");
    XCTAssertNotEqual((id)state.lightColors, sourceLight);
}

- (void)testEditingMarksDirtyWithoutMutatingBuiltinPreset {
    NSDictionary *presets = [DirectColorThemeEditorState builtInPresets];
    NSString *original = presets[@"catppuccin"][@"light"][@"base"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:presets customThemes:@[]];
    [state selectIdentifier:@"builtin:catppuccin"];
    XCTAssertTrue([state setColor:@"#abcdef" forKey:@"base" appearance:DirectColorThemeAppearanceLight]);
    XCTAssertTrue(state.dirty);
    XCTAssertEqualObjects(state.lightColors[@"base"], @"#ABCDEF");
    XCTAssertEqualObjects(presets[@"catppuccin"][@"light"][@"base"], original);
    XCTAssertEqual(state.unsavedAction, DirectColorThemeUnsavedActionSaveAs);
}

- (void)testCustomSelectionLoadsTenColorsAndAppearanceSwitchPreservesEdits {
    DirectColorTheme *theme = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[theme]];
    XCTAssertTrue([state selectIdentifier:[@"custom:" stringByAppendingString:theme.identifier]]);
    XCTAssertFalse(state.isBuiltIn);
    XCTAssertEqual(state.lightColors.count, 10u);
    XCTAssertEqualObjects(state.advancedOverrides[@"light"][@"raw_light"], @"#ABCDEF");
    [state setColor:@"#A1B2C3" forKey:@"base" appearance:DirectColorThemeAppearanceLight];
    state.appearance = DirectColorThemeAppearanceDark;
    [state setColor:@"#D4E5F6" forKey:@"base" appearance:DirectColorThemeAppearanceDark];
    state.appearance = DirectColorThemeAppearanceLight;
    XCTAssertEqualObjects(state.lightColors[@"base"], @"#A1B2C3");
    XCTAssertEqualObjects(state.darkColors[@"base"], @"#D4E5F6");
    XCTAssertEqual(state.unsavedAction, DirectColorThemeUnsavedActionSave);
}

- (void)testSelectionChangeSaveDiscardCancelSemantics {
    DirectColorTheme *theme = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[theme]];
    [state selectIdentifier:[@"custom:" stringByAppendingString:theme.identifier]];
    [state setColor:@"#A1B2C3" forKey:@"base" appearance:DirectColorThemeAppearanceLight];
    __block NSUInteger saves = 0;
    XCTAssertFalse([state changeSelectionTo:@"builtin:gruvbox" decision:DirectColorThemeUnsavedDecisionCancel saveHandler:^{ saves++; return YES; }]);
    XCTAssertTrue([state.selectedIdentifier hasPrefix:@"custom:"]);
    XCTAssertEqual(saves, 0u);
    XCTAssertTrue([state changeSelectionTo:@"builtin:gruvbox" decision:DirectColorThemeUnsavedDecisionSave saveHandler:^{ saves++; return YES; }]);
    XCTAssertEqual(saves, 1u);
    XCTAssertEqualObjects(state.selectedIdentifier, @"builtin:gruvbox");

    [state setColor:@"#010203" forKey:@"base" appearance:DirectColorThemeAppearanceLight];
    XCTAssertTrue([state changeSelectionTo:@"builtin:tokyo-night" decision:DirectColorThemeUnsavedDecisionDiscard saveHandler:nil]);
    XCTAssertEqualObjects(state.selectedIdentifier, @"builtin:tokyo-night");
    XCTAssertFalse(state.dirty);
}

- (void)testActiveLegacyPresetResolutionUsesSnapshotOverrides {
    NSDictionary *active = @{@"preset":@"gruvbox", @"light":[self colorsWithSeed:0x303030],
                             @"dark":[self colorsWithSeed:0x404040], @"advanced":@{@"light":@{}, @"dark":@{}}};
    DirectColorThemeEditorState *state = [DirectColorThemeEditorState stateForActiveConfiguration:active
        builtInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[]];
    XCTAssertEqualObjects(state.selectedIdentifier, @"builtin:gruvbox");
    XCTAssertEqualObjects(state.lightColors[@"base"], @"#303030");
    XCTAssertFalse(state.dirty);
}

- (void)testActiveCustomSnapshotResolutionWithExistingSourceUsesSnapshot {
    DirectColorTheme *theme = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    NSDictionary *active = @{@"schema_version":@2, @"preset":NSNull.null, @"custom_theme_id":theme.identifier,
        @"light":[self colorsWithSeed:0x505050], @"dark":[self colorsWithSeed:0x606060],
        @"advanced":@{@"light":@{}, @"dark":@{}}};
    DirectColorThemeEditorState *state = [DirectColorThemeEditorState stateForActiveConfiguration:active
        builtInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[theme]];
    XCTAssertEqualObjects(state.selectedIdentifier, [@"custom:" stringByAppendingString:theme.identifier]);
    XCTAssertEqualObjects(state.lightColors[@"base"], @"#505050");
    XCTAssertNil(state.warning);
}

- (void)testMissingCustomSourceRetainsSnapshotAndWarning {
    NSString *identifier = @"22222222-2222-2222-2222-222222222222";
    NSDictionary *active = @{@"schema_version":@2, @"preset":NSNull.null, @"custom_theme_id":identifier,
        @"light":[self colorsWithSeed:0x707070], @"dark":[self colorsWithSeed:0x808080],
        @"advanced":@{@"light":@{}, @"dark":@{}}};
    DirectColorThemeEditorState *state = [DirectColorThemeEditorState stateForActiveConfiguration:active
        builtInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[]];
    XCTAssertEqualObjects(state.selectedIdentifier, [@"custom:" stringByAppendingString:identifier]);
    XCTAssertEqualObjects(state.lightColors[@"base"], @"#707070");
    XCTAssertEqualObjects(state.warning, @"上次应用的自定义主题源文件已不存在；微信仍使用最后应用快照。请选择或新建主题后重新应用。");
}

- (void)testLegacyOverridesRemainCleanButRequireSaveAsForApply {
    NSDictionary *active = @{@"preset":@"gruvbox", @"light":[self colorsWithSeed:0x303030],
                             @"dark":[self colorsWithSeed:0x404040], @"advanced":@{@"light":@{}, @"dark":@{}}};
    DirectColorThemeEditorState *state = [DirectColorThemeEditorState stateForActiveConfiguration:active
        builtInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[]];
    XCTAssertFalse(state.dirty);
    XCTAssertTrue(state.requiresSaveAsForApply);
    XCTAssertEqual(state.unsavedAction, DirectColorThemeUnsavedActionNone);
}

- (void)testOperationDecisionMatrix {
    NSArray<NSNumber *> *operations = @[@(DirectColorThemeOperationSelection), @(DirectColorThemeOperationClose),
        @(DirectColorThemeOperationNew), @(DirectColorThemeOperationDuplicate), @(DirectColorThemeOperationRename),
        @(DirectColorThemeOperationDelete), @(DirectColorThemeOperationReload)];
    for (NSNumber *operation in operations) {
        for (NSNumber *action in @[@(DirectColorThemeUnsavedActionSave), @(DirectColorThemeUnsavedActionSaveAs)]) {
            XCTAssertFalse([DirectColorThemeEditorState operation:operation.integerValue mayProceedWithAction:action.integerValue decision:DirectColorThemeUnsavedDecisionCancel saveSucceeded:YES]);
            XCTAssertTrue([DirectColorThemeEditorState operation:operation.integerValue mayProceedWithAction:action.integerValue decision:DirectColorThemeUnsavedDecisionDiscard saveSucceeded:NO]);
            XCTAssertTrue([DirectColorThemeEditorState operation:operation.integerValue mayProceedWithAction:action.integerValue decision:DirectColorThemeUnsavedDecisionSave saveSucceeded:YES]);
            XCTAssertFalse([DirectColorThemeEditorState operation:operation.integerValue mayProceedWithAction:action.integerValue decision:DirectColorThemeUnsavedDecisionSave saveSucceeded:NO]);
        }
        XCTAssertTrue([DirectColorThemeEditorState operation:operation.integerValue mayProceedWithAction:DirectColorThemeUnsavedActionNone decision:DirectColorThemeUnsavedDecisionCancel saveSucceeded:NO]);
    }
}

- (void)testCustomApplyAlwaysSavesVisibleStateThenUsesReloadedAuthoritativeSnapshot {
    DirectColorTheme *source = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:DirectColorThemeEditorState.builtInPresets customThemes:@[source]];
    [state selectIdentifier:[@"custom:" stringByAppendingString:source.identifier]];
    [state setColor:@"#abcdef" forKey:@"base" appearance:DirectColorThemeAppearanceLight];
    [state markClean]; // Active snapshot can diverge while the editor is logically clean.
    __block DirectColorTheme *saved = nil;
    __block NSUInteger saves = 0, reloads = 0;
    DirectColorThemeApplyResult *result = [DirectColorThemeApplyCoordinator prepareCustomApplicationForState:state sourceTheme:source saveHandler:^BOOL(DirectColorTheme *theme, NSError **error) {
        (void)error; saves++; saved = theme; return YES;
    } reloadHandler:^NSArray<DirectColorTheme *> *(NSError **error) {
        (void)error; reloads++;
        NSMutableDictionary *document = [saved.dictionaryRepresentation mutableCopy];
        NSMutableDictionary *light = [document[@"light"] mutableCopy]; light[@"link"] = @"#123456"; document[@"light"] = light;
        return @[[DirectColorTheme themeFromDictionary:document error:nil]];
    } error:nil];
    XCTAssertNotNil(result);
    XCTAssertEqual(saves, 1u);
    XCTAssertEqual(reloads, 1u);
    XCTAssertEqualObjects(saved.lightColors[@"base"], @"#ABCDEF");
    XCTAssertEqualObjects(result.applicationSnapshot[@"light"][@"base"], @"#ABCDEF");
    XCTAssertEqualObjects(result.applicationSnapshot[@"light"][@"link"], @"#123456");
    XCTAssertEqualObjects(result.authoritativeTheme.applicationSnapshot, result.applicationSnapshot);
}

- (void)testCustomApplySaveFailureDoesNotReloadOrProduceSnapshot {
    DirectColorTheme *source = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:DirectColorThemeEditorState.builtInPresets customThemes:@[source]];
    [state selectIdentifier:[@"custom:" stringByAppendingString:source.identifier]];
    __block NSUInteger reloads = 0;
    NSError *error = nil;
    DirectColorThemeApplyResult *result = [DirectColorThemeApplyCoordinator prepareCustomApplicationForState:state sourceTheme:source saveHandler:^BOOL(DirectColorTheme *theme, NSError **saveError) {
        (void)theme; if (saveError) *saveError = [NSError errorWithDomain:@"test" code:7 userInfo:nil]; return NO;
    } reloadHandler:^NSArray<DirectColorTheme *> *(NSError **reloadError) {
        (void)reloadError; reloads++; return @[source];
    } error:&error];
    XCTAssertNil(result);
    XCTAssertEqual(reloads, 0u);
    XCTAssertEqual(error.code, 7);
    XCTAssertEqualObjects(state.selectedIdentifier, [@"custom:" stringByAppendingString:source.identifier]);
}

- (void)testCustomApplyReloadCachedThemesWithErrorFailsWithoutSnapshot {
    DirectColorTheme *source = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:DirectColorThemeEditorState.builtInPresets customThemes:@[source]];
    [state selectIdentifier:[@"custom:" stringByAppendingString:source.identifier]];
    __block NSUInteger saves = 0, reloads = 0;
    NSError *error = nil;
    DirectColorThemeApplyResult *result = [DirectColorThemeApplyCoordinator prepareCustomApplicationForState:state sourceTheme:source saveHandler:^BOOL(DirectColorTheme *theme, NSError **saveError) {
        (void)theme; (void)saveError; saves++; return YES;
    } reloadHandler:^NSArray<DirectColorTheme *> *(NSError **reloadError) {
        reloads++;
        if (reloadError) *reloadError = [NSError errorWithDomain:@"production-cache" code:19 userInfo:@{NSLocalizedDescriptionKey:@"Could not list theme documents."}];
        return @[source]; // DirectColorThemeStore production contract: cached themes plus NSError.
    } error:&error];
    XCTAssertNil(result);
    XCTAssertEqual(saves, 1u);
    XCTAssertEqual(reloads, 1u);
    XCTAssertEqual(error.code, 19);
}

- (void)assertCreationOperation:(DirectColorThemeOperation)operation
                 unsavedAction:(DirectColorThemeUnsavedAction)action
                      decision:(DirectColorThemeUnsavedDecision)decision
                 saveSucceeds:(BOOL)saveSucceeds
                expectedSaveAs:(NSUInteger)expectedSaveAs
                  expectedSave:(NSUInteger)expectedSave
               expectedCurrent:(NSUInteger)expectedCurrent
                expectedTarget:(NSUInteger)expectedTarget {
    __block NSUInteger saveAsCount = 0, saveCount = 0, currentCount = 0, targetCount = 0;
    DirectColorThemeOperationResult *result = [DirectColorThemeOperationCoordinator performOperation:operation
        unsavedAction:action decision:decision
        saveHandler:^BOOL{ saveCount++; return saveSucceeds; }
        saveAsHandler:^BOOL{ saveAsCount++; return saveSucceeds; }
        currentHandler:^{ currentCount++; }
        targetHandler:^{ targetCount++; }];
    XCTAssertEqual(saveAsCount, expectedSaveAs);
    XCTAssertEqual(saveCount, expectedSave);
    XCTAssertEqual(currentCount, expectedCurrent);
    XCTAssertEqual(targetCount, expectedTarget);
    XCTAssertEqual(result.targetActionCount, expectedTarget);
    XCTAssertEqual(result.currentActionCount, expectedCurrent);
}

- (void)testNewAndDuplicateCreationOrchestrationExecutesTargetAtMostOnce {
    for (NSNumber *operation in @[@(DirectColorThemeOperationNew), @(DirectColorThemeOperationDuplicate)]) {
        DirectColorThemeOperation op = operation.integerValue;
        // Built-in Save As creates the requested New/Duplicate from visible values; no second creation.
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSaveAs decision:DirectColorThemeUnsavedDecisionSave saveSucceeds:YES expectedSaveAs:1 expectedSave:0 expectedCurrent:0 expectedTarget:0];
        // Custom Save resolves only the current edit, then performs the requested creation once.
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSave decision:DirectColorThemeUnsavedDecisionSave saveSucceeds:YES expectedSaveAs:0 expectedSave:1 expectedCurrent:0 expectedTarget:1];
        // Discard resolves only current editing, then performs the requested creation once.
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSaveAs decision:DirectColorThemeUnsavedDecisionDiscard saveSucceeds:NO expectedSaveAs:0 expectedSave:0 expectedCurrent:1 expectedTarget:1];
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSave decision:DirectColorThemeUnsavedDecisionDiscard saveSucceeds:NO expectedSaveAs:0 expectedSave:0 expectedCurrent:1 expectedTarget:1];
        // Cancel and either save failure stop before the target action.
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSaveAs decision:DirectColorThemeUnsavedDecisionCancel saveSucceeds:YES expectedSaveAs:0 expectedSave:0 expectedCurrent:0 expectedTarget:0];
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSave decision:DirectColorThemeUnsavedDecisionCancel saveSucceeds:YES expectedSaveAs:0 expectedSave:0 expectedCurrent:0 expectedTarget:0];
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSaveAs decision:DirectColorThemeUnsavedDecisionSave saveSucceeds:NO expectedSaveAs:1 expectedSave:0 expectedCurrent:0 expectedTarget:0];
        [self assertCreationOperation:op unsavedAction:DirectColorThemeUnsavedActionSave decision:DirectColorThemeUnsavedDecisionSave saveSucceeds:NO expectedSaveAs:0 expectedSave:1 expectedCurrent:0 expectedTarget:0];
    }
}

- (void)testInvalidActiveAdvancedDoesNotEnterInvalidSnapshotState {
    DirectColorTheme *source = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    NSDictionary *active = @{@"schema_version":@2, @"preset":NSNull.null, @"custom_theme_id":source.identifier,
        @"light":[self colorsWithSeed:0x505050], @"dark":[self colorsWithSeed:0x606060],
        @"advanced":@{@"light":@{@"bad":@42}, @"dark":@{}}};
    DirectColorThemeEditorState *state = [DirectColorThemeEditorState stateForActiveConfiguration:active
        builtInPresets:DirectColorThemeEditorState.builtInPresets customThemes:@[source]];
    XCTAssertEqualObjects(state.lightColors, source.lightColors);
    XCTAssertEqualObjects(state.advancedOverrides, source.advancedOverrides);
    XCTAssertNotNil(state.warning);
}

- (void)testNonObjectActiveConfigurationProducesExplicitError {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[@"legal", @"json"] options:0 error:nil];
    NSError *error = nil;
    XCTAssertNil([DirectColorThemeEditorState activeConfigurationFromJSONData:data error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"object"]);
}

- (void)testInvalidLegacyAdvancedDoesNotDisplayUnvalidatedOverrides {
    NSDictionary *active = @{@"preset":@"gruvbox", @"light":[self colorsWithSeed:0x303030],
        @"dark":[self colorsWithSeed:0x404040], @"advanced":@{@"light":@[], @"dark":@{}}};
    DirectColorThemeEditorState *state = [DirectColorThemeEditorState stateForActiveConfiguration:active
        builtInPresets:DirectColorThemeEditorState.builtInPresets customThemes:@[]];
    XCTAssertEqualObjects(state.lightColors, DirectColorThemeEditorState.builtInPresets[@"gruvbox"][@"light"]);
    XCTAssertFalse(state.requiresSaveAsForApply);
    XCTAssertNotNil(state.warning);
}

- (void)testSchemaTwoSnapshotHasOnlyDirectColorsAndNoPalette {
    DirectColorTheme *theme = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[theme]];
    [state selectIdentifier:[@"custom:" stringByAppendingString:theme.identifier]];
    NSDictionary *snapshot = theme.applicationSnapshot;
    NSSet *expectedKeys = [NSSet setWithArray:@[@"schema_version", @"preset", @"custom_theme_id", @"light", @"dark", @"advanced"]];
    XCTAssertEqualObjects([NSSet setWithArray:snapshot.allKeys], expectedKeys);
    XCTAssertEqual([snapshot[@"light"] count], 10u);
    XCTAssertEqual([snapshot[@"dark"] count], 10u);
    XCTAssertNil(snapshot[@"palette"]);
}

@end
