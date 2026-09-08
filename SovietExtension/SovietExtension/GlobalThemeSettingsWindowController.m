//
//  GlobalThemeSettingsWindowController.m
//  SovietExtension
//

#import "GlobalThemeSettingsWindowController.h"
#import "CappuccinoPatch.h"

static NSString * const YMGlobalThemePresetKey = @"kGlobalThemePreset.SOVIET";
static NSString * const YMGlobalThemeLightColorsKey = @"kGlobalThemeLightColors.SOVIET";
static NSString * const YMGlobalThemeDarkColorsKey = @"kGlobalThemeDarkColors.SOVIET";
static NSString * const YMGlobalThemeAdvancedKey = @"kGlobalThemeAdvanced.SOVIET";

static NSArray<NSString *> *YMCoreColorKeys(void) {
    return @[@"base", @"ribbon", @"outgoing_bubble", @"incoming_bubble",
             @"text", @"subtext", @"link", @"accent"];
}

static NSDictionary<NSString *, NSString *> *YMCoreColorTitles(void) {
    return @{@"base": @"主背景", @"ribbon": @"左侧 Ribbon", @"outgoing_bubble": @"发送气泡",
             @"incoming_bubble": @"接收气泡", @"text": @"主要文字", @"subtext": @"次要文字",
             @"link": @"链接", @"accent": @"强调 / 选中"};
}

static NSDictionary *YMThemePresets(void) {
    return @{
        @"catppuccin": @{
            @"title": @"Catppuccin",
            @"light": @{@"base":@"#EFF1F5", @"ribbon":@"#DCE0E8", @"outgoing_bubble":@"#BCC0CC", @"incoming_bubble":@"#CCD0DA", @"text":@"#4C4F69", @"subtext":@"#6C6F85", @"link":@"#1E66F5", @"accent":@"#7287FD"},
            @"dark": @{@"base":@"#1E1E2E", @"ribbon":@"#303446", @"outgoing_bubble":@"#9399B2", @"incoming_bubble":@"#313244", @"text":@"#CDD6F4", @"subtext":@"#A6ADC8", @"link":@"#89B4FA", @"accent":@"#B4BEFE"},
            @"advanced": @{@"dark": @{@"bg0": @"#313244"}}},
        @"catppuccin-frappe": @{
            @"title": @"Catppuccin · Frappé",
            @"light": @{@"base":@"#EFF1F5", @"ribbon":@"#DCE0E8", @"outgoing_bubble":@"#DCE8D5", @"incoming_bubble":@"#F7F7F9", @"text":@"#4C4F69", @"subtext":@"#5C5F77", @"link":@"#1E66F5", @"accent":@"#179299"},
            @"dark": @{@"base":@"#303446", @"ribbon":@"#292C3C", @"outgoing_bubble":@"#B5D09F", @"incoming_bubble":@"#414559", @"text":@"#C6D0F5", @"subtext":@"#B5BFE2", @"link":@"#8CAAEE", @"accent":@"#81C8BE"}},
        @"catppuccin-macchiato": @{
            @"title": @"Catppuccin · Macchiato",
            @"light": @{@"base":@"#EFF1F5", @"ribbon":@"#DCE0E8", @"outgoing_bubble":@"#DCE8D5", @"incoming_bubble":@"#F7F7F9", @"text":@"#4C4F69", @"subtext":@"#5C5F77", @"link":@"#1E66F5", @"accent":@"#179299"},
            @"dark": @{@"base":@"#24273A", @"ribbon":@"#1E2030", @"outgoing_bubble":@"#B5D7A5", @"incoming_bubble":@"#363A4F", @"text":@"#CAD3F5", @"subtext":@"#B8C0E0", @"link":@"#8AADF4", @"accent":@"#8BD5CA"}},
        @"gruvbox": @{
            @"title": @"Gruvbox",
            @"light": @{@"base":@"#FBF1C7", @"ribbon":@"#EBDBB2", @"outgoing_bubble":@"#D5C4A1", @"incoming_bubble":@"#EBDBB2", @"text":@"#3C3836", @"subtext":@"#665C54", @"link":@"#076678", @"accent":@"#D65D0E"},
            @"dark": @{@"base":@"#282828", @"ribbon":@"#1D2021", @"outgoing_bubble":@"#A89984", @"incoming_bubble":@"#3C3836", @"text":@"#EBDBB2", @"subtext":@"#BDAE93", @"link":@"#83A598", @"accent":@"#FE8019"}},
        @"tokyo-night": @{
            @"title": @"Tokyo Night",
            @"light": @{@"base":@"#D5D6DB", @"ribbon":@"#CBCCD1", @"outgoing_bubble":@"#B7C1E3", @"incoming_bubble":@"#C4C8DA", @"text":@"#343B58", @"subtext":@"#565A6E", @"link":@"#34548A", @"accent":@"#5A4A78"},
            @"dark": @{@"base":@"#1A1B26", @"ribbon":@"#16161E", @"outgoing_bubble":@"#7AA2D6", @"incoming_bubble":@"#24283B", @"text":@"#C0CAF5", @"subtext":@"#A9B1D6", @"link":@"#7AA2F7", @"accent":@"#BB9AF7"}}
    };
}

static NSColor *YMColorFromHex(NSString *hex) {
    NSString *value = [[hex ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if (value.length != 6) return NSColor.magentaColor;
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:value] scanHexInt:&rgb]) return NSColor.magentaColor;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0
                              green:((rgb >> 8) & 0xff) / 255.0
                               blue:(rgb & 0xff) / 255.0 alpha:1.0];
}

static NSString *YMHexFromColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [rgb getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lrint(r * 255), (int)lrint(g * 255), (int)lrint(b * 255)];
}

@interface YMThemePreviewView : NSView
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *colors;
@end

@implementation YMThemePreviewView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSDictionary *c = self.colors ?: @{};
    NSColor *base = YMColorFromHex(c[@"base"]);
    NSColor *ribbon = YMColorFromHex(c[@"ribbon"]);
    NSColor *incoming = YMColorFromHex(c[@"incoming_bubble"]);
    NSColor *outgoing = YMColorFromHex(c[@"outgoing_bubble"]);
    NSColor *text = YMColorFromHex(c[@"text"]);
    NSColor *subtext = YMColorFromHex(c[@"subtext"]);
    NSColor *accent = YMColorFromHex(c[@"accent"]);
    [base setFill]; NSRectFill(self.bounds);
    [ribbon setFill]; NSRectFill(NSMakeRect(0, 0, 62, NSHeight(self.bounds)));
    [accent setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(17, 24, 28, 28) xRadius:8 yRadius:8] fill];
    [subtext setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(76, 24, 96, 9) xRadius:4 yRadius:4] fill];
    [[subtext colorWithAlphaComponent:0.48] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(76, 41, 138, 7) xRadius:3 yRadius:3] fill];
    [incoming setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(78, 78, 188, 48) xRadius:13 yRadius:13] fill];
    [outgoing setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSWidth(self.bounds)-242, 140, 218, 48) xRadius:13 yRadius:13] fill];
    NSDictionary *attrs = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium], NSForegroundColorAttributeName:text};
    [@"你好，这是主题实时预览" drawAtPoint:NSMakePoint(94, 94) withAttributes:attrs];
    [@"发送气泡与文字对比" drawAtPoint:NSMakePoint(NSWidth(self.bounds)-226, 156) withAttributes:attrs];
}
@end

@interface GlobalThemeSettingsWindowController () <NSTextViewDelegate>
@property (nonatomic, strong) NSPopUpButton *presetPopup;
@property (nonatomic, strong) NSSegmentedControl *appearanceControl;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSColorWell *> *colorWells;
@property (nonatomic, strong) NSMutableDictionary *lightColors;
@property (nonatomic, strong) NSMutableDictionary *darkColors;
@property (nonatomic, strong) YMThemePreviewView *previewView;
@property (nonatomic, strong) NSTextView *advancedTextView;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation GlobalThemeSettingsWindowController

+ (void)registerDefaults {
    NSDictionary *preset = YMThemePresets()[@"catppuccin"];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        YMGlobalThemePresetKey: @"catppuccin",
        YMGlobalThemeLightColorsKey: preset[@"light"],
        YMGlobalThemeDarkColorsKey: preset[@"dark"],
        YMGlobalThemeAdvancedKey: @"{\n  \"dark\": {\n    \"bg0\": \"#313244\"\n  }\n}"
    }];
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 760, 790);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"全局主题设置";
    panel.releasedWhenClosed = NO;
    panel.minSize = NSMakeSize(720, 720);
    self = [super initWithWindow:panel];
    if (self) {
        self.colorWells = [NSMutableDictionary dictionary];
        [self ym_buildUI:panel.contentView];
        [self ym_loadSettings];
    }
    return self;
}

- (void)showWindowCentered {
    [GlobalThemeSettingsWindowController registerDefaults];
    [self ym_loadSettings];
    if (!self.window.visible) [self.window center];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (NSTextField *)ym_label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text; label.font = font; label.textColor = color;
    label.bezeled = NO; label.drawsBackground = NO; label.editable = NO; label.selectable = NO;
    return label;
}

- (void)ym_buildUI:(NSView *)content {
    content.wantsLayer = YES;
    content.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    [content addSubview:[self ym_label:@"全局主题" frame:NSMakeRect(28, 742, 250, 30) font:[NSFont systemFontOfSize:23 weight:NSFontWeightSemibold] color:NSColor.labelColor]];
    [content addSubview:[self ym_label:@"预览即时更新；应用后将安全写入主题表、重新签名并重启微信" frame:NSMakeRect(28, 716, 610, 20) font:[NSFont systemFontOfSize:12] color:NSColor.secondaryLabelColor]];

    [content addSubview:[self ym_label:@"主题预设" frame:NSMakeRect(28, 674, 90, 24) font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] color:NSColor.labelColor]];
    self.presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, 670, 205, 30) pullsDown:NO];
    for (NSString *key in @[@"catppuccin", @"catppuccin-frappe", @"catppuccin-macchiato", @"gruvbox", @"tokyo-night"]) {
        [self.presetPopup addItemWithTitle:YMThemePresets()[key][@"title"]];
        self.presetPopup.lastItem.representedObject = key;
    }
    self.presetPopup.target = self; self.presetPopup.action = @selector(presetChanged:);
    [content addSubview:self.presetPopup];

    self.appearanceControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(500, 670, 230, 30)];
    self.appearanceControl.segmentCount = 2;
    [self.appearanceControl setLabel:@"浅色" forSegment:0]; [self.appearanceControl setLabel:@"深色" forSegment:1];
    self.appearanceControl.selectedSegment = 0; self.appearanceControl.target = self; self.appearanceControl.action = @selector(appearanceChanged:);
    [content addSubview:self.appearanceControl];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(28, 652, 704, 1)]; separator.boxType = NSBoxSeparator; [content addSubview:separator];
    [content addSubview:[self ym_label:@"核心颜色" frame:NSMakeRect(28, 615, 120, 24) font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold] color:NSColor.labelColor]];

    NSArray *keys = YMCoreColorKeys(); NSDictionary *titles = YMCoreColorTitles();
    for (NSInteger i = 0; i < keys.count; i++) {
        NSInteger column = i / 4, row = i % 4;
        CGFloat x = 28 + column * 194, y = 570 - row * 47;
        NSString *key = keys[i];
        [content addSubview:[self ym_label:titles[key] frame:NSMakeRect(x, y, 112, 26) font:[NSFont systemFontOfSize:12] color:NSColor.labelColor]];
        NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + 116, y + 1, 58, 25)];
        well.target = self; well.action = @selector(colorChanged:); well.tag = i;
        self.colorWells[key] = well; [content addSubview:well];
    }

    self.previewView = [[YMThemePreviewView alloc] initWithFrame:NSMakeRect(420, 435, 312, 174)];
    self.previewView.wantsLayer = YES; self.previewView.layer.cornerRadius = 12; self.previewView.layer.masksToBounds = YES;
    self.previewView.layer.borderWidth = 1; self.previewView.layer.borderColor = NSColor.separatorColor.CGColor;
    [content addSubview:self.previewView];
    [content addSubview:[self ym_label:@"切换“浅色 / 深色”编辑对应外观；运行时自动跟随 macOS。" frame:NSMakeRect(420, 408, 312, 20) font:[NSFont systemFontOfSize:11] color:NSColor.secondaryLabelColor]];

    NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(28, 392, 150, 30)];
    resetButton.title = @"恢复当前预设"; resetButton.bezelStyle = NSBezelStyleRounded; resetButton.target = self; resetButton.action = @selector(resetPreset:); [content addSubview:resetButton];

    [content addSubview:[self ym_label:@"高级语义色覆盖" frame:NSMakeRect(28, 346, 180, 24) font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold] color:NSColor.labelColor]];
    [content addSubview:[self ym_label:@"可按微信 named theme key 精确覆盖。JSON 示例：" frame:NSMakeRect(28, 323, 500, 20) font:[NSFont systemFontOfSize:11] color:NSColor.secondaryLabelColor]];
    [content addSubview:[self ym_label:@"{\"chat_right_bubble_color\":{\"light\":\"#AABBCC\",\"dark\":\"#112233\"}}" frame:NSMakeRect(28, 302, 680, 20) font:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor]];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(28, 116, 704, 180)];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
    self.advancedTextView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    self.advancedTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; self.advancedTextView.delegate = self;
    scroll.documentView = self.advancedTextView; [content addSubview:scroll];

    self.statusLabel = [self ym_label:@"" frame:NSMakeRect(28, 82, 500, 22) font:[NSFont systemFontOfSize:11] color:NSColor.secondaryLabelColor]; [content addSubview:self.statusLabel];
    NSButton *close = [[NSButton alloc] initWithFrame:NSMakeRect(532, 34, 90, 34)]; close.title = @"关闭"; close.bezelStyle = NSBezelStyleRounded; close.target = self; close.action = @selector(closeWindow:); [content addSubview:close];
    NSButton *apply = [[NSButton alloc] initWithFrame:NSMakeRect(630, 34, 102, 34)]; apply.title = @"应用并重启"; apply.bezelStyle = NSBezelStyleRounded; apply.keyEquivalent = @"\r"; apply.target = self; apply.action = @selector(applyAndRestart:); [content addSubview:apply];
}

- (NSMutableDictionary *)ym_colorsForCurrentAppearance { return self.appearanceControl.selectedSegment == 1 ? self.darkColors : self.lightColors; }

- (void)ym_loadSettings {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *preset = [d stringForKey:YMGlobalThemePresetKey] ?: @"catppuccin";
    self.lightColors = [[d dictionaryForKey:YMGlobalThemeLightColorsKey] mutableCopy] ?: [YMThemePresets()[preset][@"light"] mutableCopy];
    self.darkColors = [[d dictionaryForKey:YMGlobalThemeDarkColorsKey] mutableCopy] ?: [YMThemePresets()[preset][@"dark"] mutableCopy];
    for (NSMenuItem *item in self.presetPopup.itemArray) if ([item.representedObject isEqual:preset]) { [self.presetPopup selectItem:item]; break; }
    NSString *defaultAdvanced = @"{}";
    NSDictionary *presetAdvanced = YMThemePresets()[preset][@"advanced"];
    if (presetAdvanced) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:presetAdvanced options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
        if (data) defaultAdvanced = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    }
    self.advancedTextView.string = [d stringForKey:YMGlobalThemeAdvancedKey] ?: defaultAdvanced;
    [self ym_refreshControls];
}

- (void)ym_refreshControls {
    NSDictionary *colors = [self ym_colorsForCurrentAppearance];
    for (NSString *key in YMCoreColorKeys()) self.colorWells[key].color = YMColorFromHex(colors[key]);
    self.previewView.colors = colors; [self.previewView setNeedsDisplay:YES];
}

- (void)presetChanged:(id)sender { (void)sender; [self resetPreset:nil]; }
- (void)resetPreset:(id)sender {
    (void)sender; NSString *key = self.presetPopup.selectedItem.representedObject ?: @"catppuccin";
    self.lightColors = [YMThemePresets()[key][@"light"] mutableCopy]; self.darkColors = [YMThemePresets()[key][@"dark"] mutableCopy];
    NSDictionary *advanced = YMThemePresets()[key][@"advanced"] ?: @{};
    NSData *data = [NSJSONSerialization dataWithJSONObject:advanced options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    self.advancedTextView.string = data ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}") : @"{}";
    self.statusLabel.stringValue = @"已恢复预设；尚未应用到微信"; [self ym_refreshControls];
}
- (void)appearanceChanged:(id)sender { (void)sender; [self ym_refreshControls]; }
- (void)colorChanged:(NSColorWell *)sender {
    NSString *key = YMCoreColorKeys()[sender.tag]; [self ym_colorsForCurrentAppearance][key] = YMHexFromColor(sender.color);
    self.statusLabel.stringValue = @"预览已更新；点击“应用并重启”使微信生效"; [self ym_refreshControls];
}
- (void)closeWindow:(id)sender { (void)sender; [self.window close]; }

- (NSDictionary *)ym_advancedDictionaryWithError:(NSError **)error {
    NSData *data = [self.advancedTextView.string dataUsingEncoding:NSUTF8StringEncoding];
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = [NSError errorWithDomain:@"SovietExtension.Theme" code:1 userInfo:@{NSLocalizedDescriptionKey:@"高级覆盖必须是 JSON 对象"}];
        return nil;
    }
    return object;
}

- (NSString *)ym_supportDirectory {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/SovietExtension"];
}

- (void)applyAndRestart:(id)sender {
    (void)sender; NSError *error = nil; NSDictionary *advanced = [self ym_advancedDictionaryWithError:&error];
    if (!advanced) { [self ym_showError:error.localizedDescription]; return; }
    NSString *preset = self.presetPopup.selectedItem.representedObject ?: @"catppuccin";
    NSDictionary *config = @{@"preset":preset, @"light":self.lightColors, @"dark":self.darkColors, @"advanced":advanced};
    NSString *dir = [self ym_supportDirectory];
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) { [self ym_showError:error.localizedDescription]; return; }
    NSString *configPath = [dir stringByAppendingPathComponent:@"theme.json"];
    NSData *json = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if (!json || ![json writeToFile:configPath options:NSDataWritingAtomic error:&error]) { [self ym_showError:error.localizedDescription]; return; }
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:preset forKey:YMGlobalThemePresetKey]; [d setObject:self.lightColors forKey:YMGlobalThemeLightColorsKey]; [d setObject:self.darkColors forKey:YMGlobalThemeDarkColorsKey]; [d setObject:self.advancedTextView.string forKey:YMGlobalThemeAdvancedKey]; [d setBool:YES forKey:YMCappuccinoThemeEnabledKey]; [d synchronize];

    NSString *runner = [dir stringByAppendingPathComponent:@"apply_theme.sh"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:runner]) { [self ym_showError:[NSString stringWithFormat:@"主题辅助程序不存在：%@\n请重新运行 Rely/install.sh。", runner]]; return; }
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"应用全局主题？"; alert.informativeText = @"微信将退出，主题表会从原始备份重新生成并完成 ad-hoc 签名，随后自动启动。"; [alert addButtonWithTitle:@"应用并重启"]; [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSTask *task = [[NSTask alloc] init]; task.launchPath = @"/bin/bash"; task.arguments = @[@"-c", [NSString stringWithFormat:@"nohup %@ %@ >/tmp/SovietExtension-theme-apply.log 2>&1 </dev/null &", [self ym_shellQuote:runner], [self ym_shellQuote:configPath]]];
    @try { [task launch]; [task waitUntilExit]; } @catch (NSException *exception) { [self ym_showError:exception.reason]; return; }
    self.statusLabel.stringValue = @"正在应用主题并重启微信…"; if (self.applyHandler) self.applyHandler(YES); [self.window close];
}

- (NSString *)ym_shellQuote:(NSString *)value { return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }
- (void)ym_showError:(NSString *)message { NSAlert *a = [[NSAlert alloc] init]; a.alertStyle = NSAlertStyleCritical; a.messageText = @"无法应用主题"; a.informativeText = message ?: @"未知错误"; [a runModal]; }

@end
