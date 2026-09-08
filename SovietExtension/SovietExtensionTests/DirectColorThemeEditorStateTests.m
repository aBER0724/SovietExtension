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
    NSDictionary *presets = [DirectColorThemeEditorState builtInPresets];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:presets customThemes:@[]];
    XCTAssertTrue([state selectIdentifier:@"builtin:catppuccin"]);
    XCTAssertTrue(state.isBuiltIn);
    XCTAssertEqual(state.lightColors.count, 10u);
    XCTAssertEqual(state.darkColors.count, 10u);
    XCTAssertEqualObjects([NSSet setWithArray:state.lightColors.allKeys], DirectColorTheme.requiredColorKeys);
    XCTAssertFalse([state.lightColors isEqual:presets[@"catppuccin"][@"light"]] == NO);
    XCTAssertNotEqual((id)state.lightColors, presets[@"catppuccin"][@"light"]);
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

- (void)testSchemaTwoSnapshotHasOnlyDirectColorsAndNoPalette {
    DirectColorTheme *theme = [self themeNamed:@"Ocean" identifier:@"11111111-1111-1111-1111-111111111111"];
    DirectColorThemeEditorState *state = [[DirectColorThemeEditorState alloc] initWithBuiltInPresets:[DirectColorThemeEditorState builtInPresets] customThemes:@[theme]];
    [state selectIdentifier:[@"custom:" stringByAppendingString:theme.identifier]];
    NSDictionary *snapshot = [state applicationSnapshotForCustomIdentifier:theme.identifier];
    NSSet *expectedKeys = [NSSet setWithArray:@[@"schema_version", @"preset", @"custom_theme_id", @"light", @"dark", @"advanced"]];
    XCTAssertEqualObjects([NSSet setWithArray:snapshot.allKeys], expectedKeys);
    XCTAssertEqual([snapshot[@"light"] count], 10u);
    XCTAssertEqual([snapshot[@"dark"] count], 10u);
    XCTAssertNil(snapshot[@"palette"]);
}

@end
