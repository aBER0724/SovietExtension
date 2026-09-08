#import "DirectColorThemeEditorState.h"
#import "DirectColorTheme.h"

static NSString * const MissingSourceWarning = @"上次应用的自定义主题源文件已不存在；微信仍使用最后应用快照。请选择或新建主题后重新应用。";
static NSString * const InvalidSnapshotWarning = @"上次应用的主题快照无效，已显示可用的主题源数据。请检查 theme.json 后重新应用。";
static NSString * const EditorErrorDomain = @"SovietExtension.DirectColorThemeEditorState";

static NSDictionary *Colors(NSString *base, NSString *sidebar, NSString *ribbon, NSString *outgoing,
                            NSString *incoming, NSString *text, NSString *subtext, NSString *accent,
                            NSString *link, NSString *danger) {
    return @{@"base":base, @"sidebar":sidebar, @"ribbon":ribbon, @"outgoing_bubble":outgoing,
             @"incoming_bubble":incoming, @"text":text, @"subtext":subtext, @"accent":accent,
             @"link":link, @"danger":danger};
}

static NSDictionary *EmptyAdvanced(void) { return @{@"light":@{}, @"dark":@{}}; }

static BOOL ValidColors(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![[NSSet setWithArray:[value allKeys]] isEqualToSet:DirectColorTheme.requiredColorKeys]) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^#[0-9A-Fa-f]{6}$" options:0 error:nil];
    for (id color in [value allValues]) if (![color isKindOfClass:NSString.class] || [regex numberOfMatchesInString:color options:0 range:NSMakeRange(0, [color length])] != 1) return NO;
    return YES;
}

static NSDictionary *NormalizedColors(NSDictionary *colors) {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:colors.count];
    [colors enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { result[key] = value.uppercaseString; }];
    return result;
}

static NSDictionary *StrictSnapshotValues(NSDictionary *configuration, NSError **error) {
    if (!ValidColors(configuration[@"light"]) || !ValidColors(configuration[@"dark"])) return nil;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSString *now = [formatter stringFromDate:[NSDate date]];
    NSDictionary *document = @{@"schema_version":@1, @"id":NSUUID.UUID.UUIDString, @"name":@"Active Snapshot Validation",
        @"source":@"custom", @"created_at":now, @"updated_at":now, @"light":configuration[@"light"],
        @"dark":configuration[@"dark"], @"advanced":configuration[@"advanced"] ?: EmptyAdvanced()};
    DirectColorTheme *theme = [DirectColorTheme themeFromDictionary:document error:error];
    return theme ? @{@"light":theme.lightColors, @"dark":theme.darkColors, @"advanced":theme.advancedOverrides} : nil;
}

static NSDictionary *DeepCopyPropertyList(NSDictionary *value) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : [value copy];
}

@interface DirectColorThemeEditorState ()
@property (nonatomic, copy, readwrite) NSDictionary *builtInPresets;
@property (nonatomic, copy, readwrite) NSArray<DirectColorTheme *> *customThemes;
@property (nonatomic, copy, readwrite) NSString *selectedIdentifier;
@property (nonatomic, strong, readwrite) NSMutableDictionary *lightColors;
@property (nonatomic, strong, readwrite) NSMutableDictionary *darkColors;
@property (nonatomic, copy, readwrite) NSDictionary *advancedOverrides;
@property (nonatomic, readwrite, getter=isDirty) BOOL dirty;
@property (nonatomic, readwrite) BOOL requiresSaveAsForApply;
@property (nonatomic, copy, readwrite) NSString *warning;
@end

@implementation DirectColorThemeEditorState

+ (NSDictionary *)activeConfigurationFromJSONData:(NSData *)data error:(NSError **)error {
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!object) return nil;
    if (![object isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:EditorErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"theme.json root must be a JSON object."}];
        return nil;
    }
    return object;
}

+ (BOOL)operation:(DirectColorThemeOperation)operation mayProceedWithAction:(DirectColorThemeUnsavedAction)action decision:(DirectColorThemeUnsavedDecision)decision saveSucceeded:(BOOL)saveSucceeded {
    (void)operation;
    if (action == DirectColorThemeUnsavedActionNone) return YES;
    if (decision == DirectColorThemeUnsavedDecisionCancel) return NO;
    if (decision == DirectColorThemeUnsavedDecisionDiscard) return YES;
    return saveSucceeded;
}

+ (NSDictionary *)builtInPresets {
    return @{
        @"catppuccin": @{@"title":@"Catppuccin",
            @"light":Colors(@"#EFF1F5", @"#E6E9EF", @"#DCE0E8", @"#BCC0CC", @"#CCD0DA", @"#4C4F69", @"#6C6F85", @"#7287FD", @"#1E66F5", @"#D20F39"),
            @"dark":Colors(@"#1E1E2E", @"#181825", @"#303446", @"#9399B2", @"#313244", @"#CDD6F4", @"#A6ADC8", @"#B4BEFE", @"#89B4FA", @"#F38BA8"),
            @"advanced":@{@"light":@{}, @"dark":@{@"bg0":@"#181825"}}},
        @"catppuccin-frappe": @{@"title":@"Frappé",
            @"light":Colors(@"#EFF1F5", @"#E6E9EF", @"#DCE0E8", @"#DCE8D5", @"#F7F7F9", @"#4C4F69", @"#5C5F77", @"#179299", @"#1E66F5", @"#D20F39"),
            @"dark":Colors(@"#303446", @"#292C3C", @"#232634", @"#B5D09F", @"#414559", @"#C6D0F5", @"#B5BFE2", @"#81C8BE", @"#8CAAEE", @"#E78284"), @"advanced":EmptyAdvanced()},
        @"catppuccin-macchiato": @{@"title":@"Macchiato",
            @"light":Colors(@"#EFF1F5", @"#E6E9EF", @"#DCE0E8", @"#DCE8D5", @"#F7F7F9", @"#4C4F69", @"#5C5F77", @"#179299", @"#1E66F5", @"#D20F39"),
            @"dark":Colors(@"#24273A", @"#1E2030", @"#181926", @"#B5D7A5", @"#363A4F", @"#CAD3F5", @"#B8C0E0", @"#8BD5CA", @"#8AADF4", @"#ED8796"), @"advanced":EmptyAdvanced()},
        @"gruvbox": @{@"title":@"Gruvbox",
            @"light":Colors(@"#FBF1C7", @"#F2E5BC", @"#EBDBB2", @"#D5C4A1", @"#EBDBB2", @"#3C3836", @"#665C54", @"#D65D0E", @"#076678", @"#CC241D"),
            @"dark":Colors(@"#282828", @"#242424", @"#1D2021", @"#A89984", @"#3C3836", @"#EBDBB2", @"#BDAE93", @"#FE8019", @"#83A598", @"#FB4934"), @"advanced":EmptyAdvanced()},
        @"tokyo-night": @{@"title":@"Tokyo Night",
            @"light":Colors(@"#D5D6DB", @"#D0D1D6", @"#CBCCD1", @"#B7C1E3", @"#C4C8DA", @"#343B58", @"#565A6E", @"#5A4A78", @"#34548A", @"#8C4351"),
            @"dark":Colors(@"#1A1B26", @"#1F2335", @"#16161E", @"#7AA2D6", @"#24283B", @"#C0CAF5", @"#A9B1D6", @"#BB9AF7", @"#7AA2F7", @"#F7768E"), @"advanced":EmptyAdvanced()}
    };
}

- (instancetype)initWithBuiltInPresets:(NSDictionary *)builtInPresets customThemes:(NSArray<DirectColorTheme *> *)customThemes {
    self = [super init];
    if (self) {
        _builtInPresets = DeepCopyPropertyList(builtInPresets);
        _customThemes = [customThemes copy];
        _appearance = DirectColorThemeAppearanceLight;
        [self selectIdentifier:@"builtin:catppuccin"];
    }
    return self;
}

- (BOOL)isBuiltIn { return [self.selectedIdentifier hasPrefix:@"builtin:"]; }
- (DirectColorThemeUnsavedAction)unsavedAction {
    if (!self.dirty) return DirectColorThemeUnsavedActionNone;
    return self.isBuiltIn ? DirectColorThemeUnsavedActionSaveAs : DirectColorThemeUnsavedActionSave;
}

- (DirectColorTheme *)selectedCustomTheme {
    if (![self.selectedIdentifier hasPrefix:@"custom:"]) return nil;
    NSString *identifier = [self.selectedIdentifier substringFromIndex:7];
    for (DirectColorTheme *theme in self.customThemes) if ([theme.identifier caseInsensitiveCompare:identifier] == NSOrderedSame) return theme;
    return nil;
}

- (BOOL)loadIdentifier:(NSString *)identifier {
    NSDictionary *light = nil, *dark = nil, *advanced = nil;
    if ([identifier hasPrefix:@"builtin:"]) {
        NSDictionary *preset = self.builtInPresets[[identifier substringFromIndex:8]];
        if (!preset) return NO;
        light = preset[@"light"]; dark = preset[@"dark"]; advanced = preset[@"advanced"] ?: EmptyAdvanced();
    } else if ([identifier hasPrefix:@"custom:"]) {
        DirectColorTheme *theme = nil;
        NSString *themeID = [identifier substringFromIndex:7];
        for (DirectColorTheme *candidate in self.customThemes) if ([candidate.identifier caseInsensitiveCompare:themeID] == NSOrderedSame) { theme = candidate; break; }
        if (!theme) return NO;
        identifier = [@"custom:" stringByAppendingString:theme.identifier];
        light = theme.lightColors; dark = theme.darkColors; advanced = theme.advancedOverrides;
    } else return NO;
    self.selectedIdentifier = identifier;
    self.lightColors = [NormalizedColors(light) mutableCopy];
    self.darkColors = [NormalizedColors(dark) mutableCopy];
    self.advancedOverrides = [advanced copy];
    self.dirty = NO;
    self.requiresSaveAsForApply = NO;
    self.warning = nil;
    return YES;
}

- (BOOL)selectIdentifier:(NSString *)identifier { return [self loadIdentifier:identifier]; }

- (BOOL)changeSelectionTo:(NSString *)identifier decision:(DirectColorThemeUnsavedDecision)decision saveHandler:(BOOL (^)(void))saveHandler {
    if (self.dirty) {
        if (decision == DirectColorThemeUnsavedDecisionCancel) return NO;
        if (decision == DirectColorThemeUnsavedDecisionSave && (!saveHandler || !saveHandler())) return NO;
    }
    return [self loadIdentifier:identifier];
}

- (BOOL)setColor:(NSString *)color forKey:(NSString *)key appearance:(DirectColorThemeAppearance)appearance {
    if (![DirectColorTheme.requiredColorKeys containsObject:key] || ![color isKindOfClass:NSString.class]) return NO;
    NSString *normalized = color.uppercaseString;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^#[0-9A-F]{6}$" options:0 error:nil];
    if ([regex numberOfMatchesInString:normalized options:0 range:NSMakeRange(0, normalized.length)] != 1) return NO;
    NSMutableDictionary *colors = appearance == DirectColorThemeAppearanceDark ? self.darkColors : self.lightColors;
    if (![colors[key] isEqualToString:normalized]) { colors[key] = normalized; self.dirty = YES; }
    return YES;
}

- (BOOL)updateAdvancedOverrides:(NSDictionary *)advancedOverrides {
    if (![advancedOverrides isKindOfClass:NSDictionary.class] || ![[NSSet setWithArray:advancedOverrides.allKeys] isEqualToSet:[NSSet setWithArray:@[@"light", @"dark"]]]) return NO;
    if (![advancedOverrides[@"light"] isKindOfClass:NSDictionary.class] || ![advancedOverrides[@"dark"] isKindOfClass:NSDictionary.class]) return NO;
    if (![self.advancedOverrides isEqual:advancedOverrides]) { self.advancedOverrides = [advancedOverrides copy]; self.dirty = YES; }
    return YES;
}

- (void)markClean { self.dirty = NO; }

+ (instancetype)stateForActiveConfiguration:(NSDictionary *)configuration builtInPresets:(NSDictionary *)builtInPresets customThemes:(NSArray<DirectColorTheme *> *)customThemes {
    DirectColorThemeEditorState *state = [[self alloc] initWithBuiltInPresets:builtInPresets customThemes:customThemes];
    if (![configuration isKindOfClass:NSDictionary.class]) return state;
    NSString *preset = [configuration[@"preset"] isKindOfClass:NSString.class] ? configuration[@"preset"] : nil;
    NSString *customID = [configuration[@"custom_theme_id"] isKindOfClass:NSString.class] ? configuration[@"custom_theme_id"] : nil;
    NSError *snapshotError = nil;
    NSDictionary *snapshot = StrictSnapshotValues(configuration, &snapshotError);
    if (customID.length) {
        DirectColorTheme *source = nil;
        for (DirectColorTheme *theme in customThemes) if ([theme.identifier caseInsensitiveCompare:customID] == NSOrderedSame) { source = theme; break; }
        if (snapshot) {
            state.selectedIdentifier = [@"custom:" stringByAppendingString:(source.identifier ?: customID.uppercaseString)];
            state.lightColors = [snapshot[@"light"] mutableCopy];
            state.darkColors = [snapshot[@"dark"] mutableCopy];
            state.advancedOverrides = snapshot[@"advanced"];
            if (!source) state.warning = MissingSourceWarning;
        } else if (source) {
            [state loadIdentifier:[@"custom:" stringByAppendingString:source.identifier]];
            state.warning = InvalidSnapshotWarning;
        } else {
            state.warning = [NSString stringWithFormat:@"%@ %@", MissingSourceWarning, InvalidSnapshotWarning];
        }
        state.dirty = NO;
    } else if (preset.length && builtInPresets[preset]) {
        [state loadIdentifier:[@"builtin:" stringByAppendingString:preset]];
        if (snapshot) {
            state.lightColors = [snapshot[@"light"] mutableCopy];
            state.darkColors = [snapshot[@"dark"] mutableCopy];
            state.advancedOverrides = snapshot[@"advanced"];
            NSDictionary *builtIn = builtInPresets[preset];
            state.requiresSaveAsForApply = ![state.lightColors isEqual:builtIn[@"light"]] ||
                ![state.darkColors isEqual:builtIn[@"dark"]] || ![state.advancedOverrides isEqual:(builtIn[@"advanced"] ?: EmptyAdvanced())];
        } else if (configuration[@"light"] || configuration[@"dark"] || configuration[@"advanced"]) {
            state.warning = InvalidSnapshotWarning;
        }
        state.dirty = NO;
    }
    return state;
}

@end

@interface DirectColorThemeOperationResult ()
@property (nonatomic, readwrite) BOOL proceeded;
@property (nonatomic, readwrite) NSUInteger saveAsCount;
@property (nonatomic, readwrite) NSUInteger saveCount;
@property (nonatomic, readwrite) NSUInteger currentActionCount;
@property (nonatomic, readwrite) NSUInteger targetActionCount;
@end
@implementation DirectColorThemeOperationResult
@end

@implementation DirectColorThemeOperationCoordinator

+ (DirectColorThemeOperationResult *)performOperation:(DirectColorThemeOperation)operation unsavedAction:(DirectColorThemeUnsavedAction)unsavedAction decision:(DirectColorThemeUnsavedDecision)decision saveHandler:(DirectColorThemeOperationSaveHandler)saveHandler saveAsHandler:(DirectColorThemeOperationSaveHandler)saveAsHandler currentHandler:(DirectColorThemeOperationActionHandler)currentHandler targetHandler:(DirectColorThemeOperationActionHandler)targetHandler {
    DirectColorThemeOperationResult *result = [[DirectColorThemeOperationResult alloc] init];
    BOOL creationOperation = operation == DirectColorThemeOperationNew || operation == DirectColorThemeOperationDuplicate;
    if (unsavedAction == DirectColorThemeUnsavedActionNone) {
        result.proceeded = YES;
    } else if (decision == DirectColorThemeUnsavedDecisionCancel) {
        return result;
    } else if (decision == DirectColorThemeUnsavedDecisionDiscard) {
        if (currentHandler) { currentHandler(); result.currentActionCount = 1; }
        result.proceeded = YES;
    } else if (unsavedAction == DirectColorThemeUnsavedActionSaveAs) {
        result.saveAsCount = 1;
        if (!saveAsHandler || !saveAsHandler()) return result;
        result.proceeded = YES;
        // For New/Duplicate, Save As already created the requested copy from visible values.
        if (creationOperation) return result;
    } else {
        result.saveCount = 1;
        if (!saveHandler || !saveHandler()) return result;
        result.proceeded = YES;
    }
    if (result.proceeded && targetHandler) { targetHandler(); result.targetActionCount = 1; }
    return result;
}

@end

@interface DirectColorThemeApplyResult ()
@property (nonatomic, strong, readwrite) DirectColorTheme *authoritativeTheme;
@property (nonatomic, copy, readwrite) NSDictionary *applicationSnapshot;
@end
@implementation DirectColorThemeApplyResult
@end

@implementation DirectColorThemeApplyCoordinator

+ (DirectColorThemeApplyResult *)prepareCustomApplicationForState:(DirectColorThemeEditorState *)state sourceTheme:(DirectColorTheme *)sourceTheme saveHandler:(DirectColorThemeSaveHandler)saveHandler reloadHandler:(DirectColorThemeReloadHandler)reloadHandler error:(NSError **)error {
    if (!state || !sourceTheme || !saveHandler || !reloadHandler) {
        if (error) *error = [NSError errorWithDomain:EditorErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"Custom theme application is missing required state."}];
        return nil;
    }
    NSMutableDictionary *document = [sourceTheme.dictionaryRepresentation mutableCopy];
    document[@"light"] = [state.lightColors copy];
    document[@"dark"] = [state.darkColors copy];
    document[@"advanced"] = [state.advancedOverrides copy];
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    document[@"updated_at"] = [formatter stringFromDate:[NSDate date]];
    DirectColorTheme *visibleModel = [DirectColorTheme themeFromDictionary:document error:error];
    if (!visibleModel || !saveHandler(visibleModel, error)) return nil;
    NSError *reloadError = nil;
    NSArray<DirectColorTheme *> *themes = reloadHandler(&reloadError);
    if (reloadError) {
        if (error) *error = reloadError;
        return nil;
    }
    if (!themes) return nil;
    DirectColorTheme *authoritative = nil;
    for (DirectColorTheme *theme in themes) if ([theme.identifier isEqualToString:visibleModel.identifier]) { authoritative = theme; break; }
    if (!authoritative) {
        if (error) *error = [NSError errorWithDomain:EditorErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey:@"Saved custom theme could not be reloaded."}];
        return nil;
    }
    DirectColorThemeApplyResult *result = [[DirectColorThemeApplyResult alloc] init];
    result.authoritativeTheme = authoritative;
    result.applicationSnapshot = authoritative.applicationSnapshot;
    return result;
}

@end
