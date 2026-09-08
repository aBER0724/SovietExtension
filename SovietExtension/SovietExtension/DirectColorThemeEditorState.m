#import "DirectColorThemeEditorState.h"
#import "DirectColorTheme.h"

static NSString * const MissingSourceWarning = @"上次应用的自定义主题源文件已不存在；微信仍使用最后应用快照。请选择或新建主题后重新应用。";

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

@interface DirectColorThemeEditorState ()
@property (nonatomic, copy, readwrite) NSDictionary *builtInPresets;
@property (nonatomic, copy, readwrite) NSArray<DirectColorTheme *> *customThemes;
@property (nonatomic, copy, readwrite) NSString *selectedIdentifier;
@property (nonatomic, strong, readwrite) NSMutableDictionary *lightColors;
@property (nonatomic, strong, readwrite) NSMutableDictionary *darkColors;
@property (nonatomic, copy, readwrite) NSDictionary *advancedOverrides;
@property (nonatomic, readwrite, getter=isDirty) BOOL dirty;
@property (nonatomic, copy, readwrite) NSString *warning;
@end

@implementation DirectColorThemeEditorState

+ (NSDictionary *)builtInPresets {
    return @{
        @"catppuccin": @{@"title":@"Catppuccin",
            @"light":Colors(@"#EFF1F5", @"#E6E9EF", @"#DCE0E8", @"#BCC0CC", @"#CCD0DA", @"#4C4F69", @"#6C6F85", @"#7287FD", @"#1E66F5", @"#D20F39"),
            @"dark":Colors(@"#1E1E2E", @"#181825", @"#303446", @"#9399B2", @"#313244", @"#CDD6F4", @"#A6ADC8", @"#B4BEFE", @"#89B4FA", @"#F38BA8"),
            @"advanced":@{@"light":@{}, @"dark":@{@"bg0":@"#313244"}}},
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
        _builtInPresets = [builtInPresets copy];
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
    BOOL snapshotValid = ValidColors(configuration[@"light"]) && ValidColors(configuration[@"dark"]);
    NSDictionary *advanced = [configuration[@"advanced"] isKindOfClass:NSDictionary.class] ? configuration[@"advanced"] : EmptyAdvanced();
    if (customID.length) {
        DirectColorTheme *source = nil;
        for (DirectColorTheme *theme in customThemes) if ([theme.identifier caseInsensitiveCompare:customID] == NSOrderedSame) { source = theme; break; }
        state.selectedIdentifier = [@"custom:" stringByAppendingString:(source.identifier ?: customID.uppercaseString)];
        if (snapshotValid) {
            state.lightColors = [NormalizedColors(configuration[@"light"]) mutableCopy];
            state.darkColors = [NormalizedColors(configuration[@"dark"]) mutableCopy];
            state.advancedOverrides = advanced;
        } else if (source) {
            state.lightColors = [source.lightColors mutableCopy]; state.darkColors = [source.darkColors mutableCopy]; state.advancedOverrides = source.advancedOverrides;
        }
        if (!source) state.warning = MissingSourceWarning;
        state.dirty = NO;
    } else if (preset.length && builtInPresets[preset]) {
        [state loadIdentifier:[@"builtin:" stringByAppendingString:preset]];
        if (snapshotValid) {
            state.lightColors = [NormalizedColors(configuration[@"light"]) mutableCopy];
            state.darkColors = [NormalizedColors(configuration[@"dark"]) mutableCopy];
            state.advancedOverrides = advanced;
            state.dirty = NO;
        }
    }
    return state;
}

- (NSDictionary *)applicationSnapshotForCustomIdentifier:(NSString *)identifier {
    return @{@"schema_version":@2, @"preset":NSNull.null, @"custom_theme_id":identifier.uppercaseString,
             @"light":[self.lightColors copy], @"dark":[self.darkColors copy], @"advanced":self.advancedOverrides ?: EmptyAdvanced()};
}

@end
