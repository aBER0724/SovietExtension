//
//  GlobalThemeSettingsWindowController.m
//  SovietExtension
//

#import "GlobalThemeSettingsWindowController.h"
#import "CappuccinoPatch.h"
#import "DirectColorTheme.h"
#import "DirectColorThemeStore.h"
#import "DirectColorThemeEditorState.h"

static NSString * const YMGlobalThemeSelectionKey = @"kGlobalThemeSelection.SOVIET";
static NSString * const YMGlobalThemeAppearanceKey = @"kGlobalThemeAppearance.SOVIET";
static NSString * const YMNewThemeCommand = @"command:new";

static NSArray<NSString *> *YMColorKeys(void) {
    return @[@"base", @"sidebar", @"ribbon", @"outgoing_bubble", @"incoming_bubble",
             @"text", @"subtext", @"accent", @"link", @"danger"];
}

static NSDictionary<NSString *, NSString *> *YMColorTitles(void) {
    return @{@"base":@"主背景", @"sidebar":@"会话侧栏", @"ribbon":@"左侧 Ribbon",
             @"outgoing_bubble":@"发送气泡", @"incoming_bubble":@"接收气泡", @"text":@"主要文字",
             @"subtext":@"次要文字", @"accent":@"强调/选中", @"link":@"链接", @"danger":@"危险/错误"};
}

static NSColor *YMColorFromHex(NSString *hex) {
    NSString *value = [hex.uppercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    unsigned int rgb = 0;
    if (value.length != 6 || ![[NSScanner scannerWithString:value] scanHexInt:&rgb]) return NSColor.magentaColor;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

static NSString *YMHexFromColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    CGFloat r = 0, g = 0, b = 0, a = 0; [rgb getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lrint(r*255), (int)lrint(g*255), (int)lrint(b*255)];
}

@interface YMThemePreviewView : NSView
@property (nonatomic, copy) NSDictionary *colors;
@end

@implementation YMThemePreviewView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect; NSDictionary *c = self.colors ?: @{};
    NSColor *base=YMColorFromHex(c[@"base"]), *sidebar=YMColorFromHex(c[@"sidebar"]), *ribbon=YMColorFromHex(c[@"ribbon"]);
    NSColor *incoming=YMColorFromHex(c[@"incoming_bubble"]), *outgoing=YMColorFromHex(c[@"outgoing_bubble"]);
    NSColor *text=YMColorFromHex(c[@"text"]), *subtext=YMColorFromHex(c[@"subtext"]), *accent=YMColorFromHex(c[@"accent"]);
    [base setFill]; NSRectFill(self.bounds); [ribbon setFill]; NSRectFill(NSMakeRect(0,0,50,NSHeight(self.bounds)));
    [sidebar setFill]; NSRectFill(NSMakeRect(50,0,95,NSHeight(self.bounds))); [accent setFill]; NSRectFill(NSMakeRect(58,15,78,8));
    [subtext setFill]; NSRectFill(NSMakeRect(58,36,65,6)); [[subtext colorWithAlphaComponent:.45] setFill]; NSRectFill(NSMakeRect(58,52,75,5));
    [incoming setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(160,35,150,42) xRadius:11 yRadius:11] fill];
    [outgoing setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSWidth(self.bounds)-180,92,160,42) xRadius:11 yRadius:11] fill];
    NSDictionary *attrs=@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:text};
    [@"接收消息与主要文字" drawAtPoint:NSMakePoint(172,49) withAttributes:attrs]; [@"发送消息" drawAtPoint:NSMakePoint(NSWidth(self.bounds)-165,106) withAttributes:attrs];
    NSDictionary *small=@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:subtext};
    [@"次要文字" drawAtPoint:NSMakePoint(160,145) withAttributes:small];
    [@"强调" drawAtPoint:NSMakePoint(220,145) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:accent}];
    [@"链接" drawAtPoint:NSMakePoint(260,145) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:YMColorFromHex(c[@"link"])}];
    [@"错误" drawAtPoint:NSMakePoint(295,145) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:YMColorFromHex(c[@"danger"])}];
}
@end

@interface GlobalThemeSettingsWindowController () <NSTextFieldDelegate, NSTextViewDelegate, NSWindowDelegate>
@property NSPopUpButton *themePopup;
@property NSSegmentedControl *appearanceControl;
@property NSMutableDictionary<NSString *, NSTextField *> *colorFields;
@property NSMutableDictionary<NSString *, NSColorWell *> *colorWells;
@property YMThemePreviewView *previewView;
@property NSTextView *advancedTextView;
@property NSTextField *statusLabel;
@property NSButton *renameButton;
@property NSButton *deleteButton;
@property DirectColorThemeStore *store;
@property DirectColorThemeEditorState *editorState;
@property BOOL refreshing;
@property BOOL allowingClose;
@end

@implementation GlobalThemeSettingsWindowController

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{YMGlobalThemeSelectionKey:@"builtin:catppuccin", YMGlobalThemeAppearanceKey:@0}];
}

- (instancetype)init {
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,820,820) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    panel.title=@"全局主题设置"; panel.releasedWhenClosed=NO; panel.contentMinSize=NSMakeSize(820,820);
    if ((self=[super initWithWindow:panel])) {
        panel.delegate=self; self.colorFields=[NSMutableDictionary dictionary]; self.colorWells=[NSMutableDictionary dictionary]; self.store=[[DirectColorThemeStore alloc] init];
        [self ym_buildUI:panel.contentView]; [self ym_reloadFromDisk];
    }
    return self;
}

- (void)showWindowCentered {
    [GlobalThemeSettingsWindowController registerDefaults];
    if (self.window.visible && ![self ym_resolveUnsavedForOperation:DirectColorThemeOperationReload]) return;
    [self ym_reloadFromDisk]; if (!self.window.visible) [self.window center]; [NSApp activateIgnoringOtherApps:YES]; [self.window makeKeyAndOrderFront:nil];
}

- (NSTextField *)ym_label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *v=[[NSTextField alloc] initWithFrame:frame]; v.stringValue=text; v.font=font; v.textColor=color; v.bezeled=NO; v.drawsBackground=NO; v.editable=NO; v.selectable=NO; return v;
}

- (NSButton *)ym_button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *b=[[NSButton alloc] initWithFrame:frame]; b.title=title; b.bezelStyle=NSBezelStyleRounded; b.target=self; b.action=action; return b;
}

- (void)ym_buildUI:(NSView *)content {
    content.wantsLayer=YES; content.layer.backgroundColor=NSColor.windowBackgroundColor.CGColor;
    NSTextField *title=[self ym_label:@"命名直色主题" frame:NSMakeRect(28,777,300,30) font:[NSFont systemFontOfSize:23 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    title.autoresizingMask=NSViewMinYMargin; [content addSubview:title];
    NSTextField *subtitle=[self ym_label:@"每个外观直接编辑十个 #RRGGBB 色值；不会生成调色板或推导颜色。" frame:NSMakeRect(28,753,650,20) font:[NSFont systemFontOfSize:12] color:NSColor.secondaryLabelColor];
    subtitle.autoresizingMask=NSViewMinYMargin|NSViewWidthSizable; [content addSubview:subtitle];
    self.themePopup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(28,710,300,30)]; self.themePopup.autoresizingMask=NSViewMinYMargin; self.themePopup.target=self; self.themePopup.action=@selector(themeChanged:); [content addSubview:self.themePopup];
    NSButton *duplicate=[self ym_button:@"另存为自定义主题" frame:NSMakeRect(340,710,150,30) action:@selector(duplicateTheme:)]; duplicate.autoresizingMask=NSViewMinYMargin; [content addSubview:duplicate];
    self.renameButton=[self ym_button:@"重命名" frame:NSMakeRect(500,710,80,30) action:@selector(renameTheme:)]; self.renameButton.autoresizingMask=NSViewMinYMargin; [content addSubview:self.renameButton];
    self.deleteButton=[self ym_button:@"删除" frame:NSMakeRect(590,710,70,30) action:@selector(deleteTheme:)]; self.deleteButton.autoresizingMask=NSViewMinYMargin; [content addSubview:self.deleteButton];
    NSButton *reload=[self ym_button:@"重新载入" frame:NSMakeRect(670,710,120,30) action:@selector(reloadThemes:)]; reload.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin; [content addSubview:reload];
    self.appearanceControl=[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(552,665,238,30)]; self.appearanceControl.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin; self.appearanceControl.segmentCount=2; [self.appearanceControl setLabel:@"浅色" forSegment:0]; [self.appearanceControl setLabel:@"深色" forSegment:1]; self.appearanceControl.target=self; self.appearanceControl.action=@selector(appearanceChanged:); [content addSubview:self.appearanceControl];
    NSTextField *colorsTitle=[self ym_label:@"直接颜色" frame:NSMakeRect(28,668,150,24) font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold] color:NSColor.labelColor]; colorsTitle.autoresizingMask=NSViewMinYMargin; [content addSubview:colorsTitle];

    NSArray *keys=YMColorKeys(); NSDictionary *titles=YMColorTitles();
    for (NSInteger i=0;i<keys.count;i++) {
        NSInteger column=i/5,row=i%5; CGFloat x=28+column*260,y=620-row*43; NSString *key=keys[i];
        NSTextField *label=[self ym_label:titles[key] frame:NSMakeRect(x,y,88,24) font:[NSFont systemFontOfSize:12] color:NSColor.labelColor]; label.autoresizingMask=NSViewMinYMargin; [content addSubview:label];
        NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(x+90,y,105,25)]; field.autoresizingMask=NSViewMinYMargin; field.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]; field.delegate=self; field.identifier=key; field.placeholderString=@"#RRGGBB"; self.colorFields[key]=field; [content addSubview:field];
        NSColorWell *well=[[NSColorWell alloc] initWithFrame:NSMakeRect(x+202,y,42,25)]; well.autoresizingMask=NSViewMinYMargin; well.tag=i; well.target=self; well.action=@selector(colorWellChanged:); self.colorWells[key]=well; [content addSubview:well];
    }
    self.previewView=[[YMThemePreviewView alloc] initWithFrame:NSMakeRect(548,447,242,176)]; self.previewView.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin; self.previewView.wantsLayer=YES; self.previewView.layer.cornerRadius=10; self.previewView.layer.masksToBounds=YES; self.previewView.layer.borderWidth=1; self.previewView.layer.borderColor=NSColor.separatorColor.CGColor; [content addSubview:self.previewView];

    NSTextField *advancedTitle=[self ym_label:@"专家设置：微信原始主题键覆盖" frame:NSMakeRect(28,380,360,24) font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold] color:NSColor.labelColor]; advancedTitle.autoresizingMask=NSViewMinYMargin; [content addSubview:advancedTitle];
    NSTextField *advancedHelp=[self ym_label:@"仅供专家使用。JSON 必须包含 light 与 dark 对象；键名由 Python 预检对真实 dylib 验证。" frame:NSMakeRect(28,358,750,20) font:[NSFont systemFontOfSize:11] color:NSColor.secondaryLabelColor]; advancedHelp.autoresizingMask=NSViewMinYMargin|NSViewWidthSizable; [content addSubview:advancedHelp];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(28,116,762,235)]; scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; scroll.hasVerticalScroller=YES; scroll.borderType=NSBezelBorder;
    self.advancedTextView=[[NSTextView alloc] initWithFrame:scroll.bounds]; self.advancedTextView.autoresizingMask=NSViewWidthSizable; self.advancedTextView.horizontallyResizable=NO; self.advancedTextView.textContainer.widthTracksTextView=YES; self.advancedTextView.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; self.advancedTextView.delegate=self; scroll.documentView=self.advancedTextView; [content addSubview:scroll];
    self.statusLabel=[self ym_label:@"" frame:NSMakeRect(28,78,580,30) font:[NSFont systemFontOfSize:11] color:NSColor.secondaryLabelColor]; self.statusLabel.autoresizingMask=NSViewWidthSizable; self.statusLabel.maximumNumberOfLines=2; [content addSubview:self.statusLabel];
    NSButton *close=[self ym_button:@"关闭" frame:NSMakeRect(596,32,90,34) action:@selector(closeWindow:)]; close.autoresizingMask=NSViewMinXMargin; [content addSubview:close];
    NSButton *apply=[self ym_button:@"应用并重启" frame:NSMakeRect(696,32,94,34) action:@selector(applyAndRestart:)]; apply.autoresizingMask=NSViewMinXMargin; apply.keyEquivalent=@"\r"; [content addSubview:apply];
}

- (NSString *)ym_supportDirectory { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/SovietExtension"]; }
- (NSString *)ym_configPath { return [[self ym_supportDirectory] stringByAppendingPathComponent:@"theme.json"]; }

- (NSDictionary *)ym_readActiveConfiguration:(NSError **)error {
    NSData *data=[NSData dataWithContentsOfFile:[self ym_configPath] options:0 error:error]; if (!data) { if (error && (*error).code==NSFileReadNoSuchFileError) *error=nil; return nil; }
    id object=[DirectColorThemeEditorState activeConfigurationFromJSONData:data error:error]; return object;
}

- (void)ym_reloadFromDisk {
    NSError *error=nil; NSArray *themes=[self.store loadThemes:&error]; NSDictionary *active=[self ym_readActiveConfiguration:&error];
    self.editorState=[DirectColorThemeEditorState stateForActiveConfiguration:active builtInPresets:DirectColorThemeEditorState.builtInPresets customThemes:themes];
    if (!active) { NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:YMGlobalThemeSelectionKey]; if (saved.length) [self.editorState selectIdentifier:saved]; }
    NSInteger appearance=[NSUserDefaults.standardUserDefaults integerForKey:YMGlobalThemeAppearanceKey]; self.editorState.appearance=appearance==1?DirectColorThemeAppearanceDark:DirectColorThemeAppearanceLight;
    [self ym_rebuildPopup]; [self ym_refreshControls];
    if (error) self.statusLabel.stringValue=error.localizedDescription; else if (self.editorState.warning) self.statusLabel.stringValue=self.editorState.warning; else if (self.store.errors.count) self.statusLabel.stringValue=self.store.errors.firstObject.localizedDescription; else self.statusLabel.stringValue=@"已载入主题";
}

- (void)ym_rebuildPopup {
    [self.themePopup removeAllItems]; NSDictionary *presets=self.editorState.builtInPresets;
    [self.themePopup addItemWithTitle:@"内置主题"]; self.themePopup.lastItem.enabled=NO;
    for (NSString *key in @[@"catppuccin",@"catppuccin-frappe",@"catppuccin-macchiato",@"gruvbox",@"tokyo-night"]) { [self.themePopup addItemWithTitle:presets[key][@"title"]]; self.themePopup.lastItem.representedObject=[@"builtin:" stringByAppendingString:key]; }
    [self.themePopup.menu addItem:NSMenuItem.separatorItem];
    [self.themePopup addItemWithTitle:@"自定义主题"]; self.themePopup.lastItem.enabled=NO;
    if (self.editorState.customThemes.count) for (DirectColorTheme *theme in self.editorState.customThemes) { [self.themePopup addItemWithTitle:theme.name]; self.themePopup.lastItem.representedObject=[@"custom:" stringByAppendingString:theme.identifier]; }
    if ([self.editorState.selectedIdentifier hasPrefix:@"custom:"] && !self.editorState.selectedCustomTheme) { [self.themePopup addItemWithTitle:@"上次应用快照（源文件缺失）"]; self.themePopup.lastItem.representedObject=self.editorState.selectedIdentifier; }
    [self.themePopup.menu addItem:NSMenuItem.separatorItem]; [self.themePopup addItemWithTitle:@"新建自定义主题…"]; self.themePopup.lastItem.representedObject=YMNewThemeCommand;
    [self ym_selectPopupIdentifier:self.editorState.selectedIdentifier];
}

- (void)ym_selectPopupIdentifier:(NSString *)identifier { for (NSMenuItem *item in self.themePopup.itemArray) if ([item.representedObject isEqual:identifier]) { [self.themePopup selectItem:item]; return; } }
- (NSDictionary *)ym_currentColors { return self.editorState.appearance==DirectColorThemeAppearanceDark?self.editorState.darkColors:self.editorState.lightColors; }

- (void)ym_refreshControls {
    self.refreshing=YES; self.appearanceControl.selectedSegment=self.editorState.appearance; NSDictionary *colors=[self ym_currentColors];
    for (NSString *key in YMColorKeys()) { self.colorFields[key].stringValue=colors[key]?:@""; self.colorWells[key].color=YMColorFromHex(colors[key]); }
    NSData *data=[NSJSONSerialization dataWithJSONObject:self.editorState.advancedOverrides options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil]; self.advancedTextView.string=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:@"{}";
    self.previewView.colors=colors; [self.previewView setNeedsDisplay:YES]; BOOL custom=self.editorState.selectedCustomTheme!=nil; self.renameButton.enabled=custom; self.deleteButton.enabled=custom; self.refreshing=NO;
}

- (BOOL)ym_syncFieldsWithError:(NSError **)error {
    for (NSString *key in YMColorKeys()) if (![self.editorState setColor:self.colorFields[key].stringValue forKey:key appearance:self.editorState.appearance]) { if(error)*error=[NSError errorWithDomain:@"SovietExtension.Theme" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@ 必须是 #RRGGBB。",YMColorTitles()[key]]}]; return NO; }
    NSData *data=[self.advancedTextView.string dataUsingEncoding:NSUTF8StringEncoding]; id advanced=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![advanced isKindOfClass:NSDictionary.class] || ![self.editorState updateAdvancedOverrides:advanced]) { if(error && !*error)*error=[NSError errorWithDomain:@"SovietExtension.Theme" code:2 userInfo:@{NSLocalizedDescriptionKey:@"专家设置必须是仅含 light、dark 两个对象的 JSON。"}]; return NO; }
    return YES;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (self.refreshing) return; NSTextField *field=notification.object; NSString *key=field.identifier; if (![YMColorKeys() containsObject:key]) return;
    if ([self.editorState setColor:field.stringValue forKey:key appearance:self.editorState.appearance]) { field.stringValue=field.stringValue.uppercaseString; field.textColor=NSColor.labelColor; self.colorWells[key].color=YMColorFromHex(field.stringValue); self.previewView.colors=[self ym_currentColors]; [self.previewView setNeedsDisplay:YES]; } else field.textColor=NSColor.systemRedColor;
    self.statusLabel.stringValue=@"有未保存修改";
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field=notification.object; NSString *key=field.identifier; if (![YMColorKeys() containsObject:key]) return;
    if ([self.editorState setColor:field.stringValue forKey:key appearance:self.editorState.appearance]) { field.stringValue=field.stringValue.uppercaseString; field.textColor=NSColor.labelColor; }
}
- (void)textDidChange:(NSNotification *)notification { if (!self.refreshing && notification.object==self.advancedTextView) self.statusLabel.stringValue=@"专家设置有未保存修改"; }
- (void)colorWellChanged:(NSColorWell *)sender { NSString *key=YMColorKeys()[sender.tag]; NSString *hex=YMHexFromColor(sender.color); self.colorFields[key].stringValue=hex; [self.editorState setColor:hex forKey:key appearance:self.editorState.appearance]; [self ym_refreshControls]; self.statusLabel.stringValue=@"有未保存修改"; }
- (void)appearanceChanged:(id)sender { (void)sender; NSError *error=nil; if (![self ym_syncFieldsWithError:&error]) { [self ym_showError:error.localizedDescription]; self.appearanceControl.selectedSegment=self.editorState.appearance; return; } self.editorState.appearance=self.appearanceControl.selectedSegment; [NSUserDefaults.standardUserDefaults setInteger:self.editorState.appearance forKey:YMGlobalThemeAppearanceKey]; [self ym_refreshControls]; }

- (DirectColorThemeUnsavedDecision)ym_unsavedDecision {
    NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"保存未完成的修改？"; a.informativeText=self.editorState.isBuiltIn?@"内置主题为只读。可另存为自定义主题，或放弃修改。":@"继续将丢弃当前尚未保存的修改。";
    [a addButtonWithTitle:self.editorState.isBuiltIn?@"另存为":@"保存"]; [a addButtonWithTitle:@"放弃"]; [a addButtonWithTitle:@"取消"];
    NSModalResponse r=[a runModal]; return r==NSAlertFirstButtonReturn?DirectColorThemeUnsavedDecisionSave:(r==NSAlertSecondButtonReturn?DirectColorThemeUnsavedDecisionDiscard:DirectColorThemeUnsavedDecisionCancel);
}

- (BOOL)ym_resolveUnsavedForOperation:(DirectColorThemeOperation)operation {
    NSError *error=nil; [self ym_syncFieldsWithError:&error];
    DirectColorThemeUnsavedAction action=self.editorState.unsavedAction;
    if (action==DirectColorThemeUnsavedActionNone && !error) return YES;
    if (action==DirectColorThemeUnsavedActionNone) action=self.editorState.isBuiltIn?DirectColorThemeUnsavedActionSaveAs:DirectColorThemeUnsavedActionSave;
    DirectColorThemeUnsavedDecision decision=[self ym_unsavedDecision];
    BOOL saved=NO;
    if (decision==DirectColorThemeUnsavedDecisionSave) saved=action==DirectColorThemeUnsavedActionSaveAs?[self ym_saveAsPrompted]:[self ym_saveCurrentCustom];
    BOOL proceed=[DirectColorThemeEditorState operation:operation mayProceedWithAction:action decision:decision saveSucceeded:saved];
    if (proceed && decision==DirectColorThemeUnsavedDecisionDiscard) { [self.editorState selectIdentifier:self.editorState.selectedIdentifier]; [self ym_refreshControls]; }
    return proceed;
}

- (void)ym_performCreationOperation:(DirectColorThemeOperation)operation {
    NSError *error=nil; [self ym_syncFieldsWithError:&error];
    DirectColorThemeUnsavedAction action=self.editorState.unsavedAction;
    if (action==DirectColorThemeUnsavedActionNone && error) action=self.editorState.isBuiltIn?DirectColorThemeUnsavedActionSaveAs:DirectColorThemeUnsavedActionSave;
    DirectColorThemeUnsavedDecision decision=action==DirectColorThemeUnsavedActionNone?DirectColorThemeUnsavedDecisionDiscard:[self ym_unsavedDecision];
    [DirectColorThemeOperationCoordinator performOperation:operation unsavedAction:action decision:decision saveHandler:^BOOL{
        return [self ym_saveCurrentCustom];
    } saveAsHandler:^BOOL{
        return [self ym_saveAsPrompted];
    } currentHandler:^{
        [self.editorState selectIdentifier:self.editorState.selectedIdentifier]; [self ym_refreshControls];
    } targetHandler:^{
        [self ym_saveAsPrompted];
    }];
}

- (void)themeChanged:(id)sender {
    (void)sender; NSString *identifier=self.themePopup.selectedItem.representedObject;
    if ([identifier isEqual:YMNewThemeCommand]) { [self ym_selectPopupIdentifier:self.editorState.selectedIdentifier]; [self newTheme:nil]; return; }
    if (![self ym_resolveUnsavedForOperation:DirectColorThemeOperationSelection]) { [self ym_selectPopupIdentifier:self.editorState.selectedIdentifier]; return; }
    BOOL changed=[self.editorState selectIdentifier:identifier];
    if (!changed) [self ym_selectPopupIdentifier:self.editorState.selectedIdentifier]; else { [NSUserDefaults.standardUserDefaults setObject:identifier forKey:YMGlobalThemeSelectionKey]; [self ym_refreshControls]; }
}

- (NSString *)ym_promptNameWithTitle:(NSString *)title defaultValue:(NSString *)value {
    NSAlert *a=[[NSAlert alloc] init]; a.messageText=title; NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,24)]; field.stringValue=value?:@""; a.accessoryView=field; [a addButtonWithTitle:@"确定"]; [a addButtonWithTitle:@"取消"]; return [a runModal]==NSAlertFirstButtonReturn?field.stringValue:nil;
}

- (DirectColorTheme *)ym_themeFromCurrentNamed:(NSString *)name identifier:(NSString *)identifier created:(NSDate *)created error:(NSError **)error {
    NSISO8601DateFormatter *f=[[NSISO8601DateFormatter alloc] init]; f.formatOptions=NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds; NSDate *now=[NSDate date];
    NSDictionary *doc=@{@"schema_version":@1,@"id":identifier,@"name":name,@"source":@"custom",@"created_at":[f stringFromDate:created?:now],@"updated_at":[f stringFromDate:now],@"light":self.editorState.lightColors,@"dark":self.editorState.darkColors,@"advanced":self.editorState.advancedOverrides};
    return [DirectColorTheme themeFromDictionary:doc error:error];
}

- (BOOL)ym_saveAsPrompted {
    NSError *error=nil; if (![self ym_syncFieldsWithError:&error]) { [self ym_showError:error.localizedDescription]; return NO; }
    NSString *name=[self ym_promptNameWithTitle:@"自定义主题名称" defaultValue:@""]; if (!name) return NO;
    DirectColorTheme *theme=[self ym_themeFromCurrentNamed:name identifier:NSUUID.UUID.UUIDString created:nil error:&error]; if (!theme || ![self.store saveTheme:theme error:&error]) { [self ym_showError:error.localizedDescription]; return NO; }
    [self.store loadThemes:nil]; self.editorState=[[DirectColorThemeEditorState alloc] initWithBuiltInPresets:DirectColorThemeEditorState.builtInPresets customThemes:self.store.themes]; [self.editorState selectIdentifier:[@"custom:" stringByAppendingString:theme.identifier]]; [self ym_rebuildPopup]; [self ym_refreshControls]; self.statusLabel.stringValue=@"自定义主题已保存"; return YES;
}

- (BOOL)ym_saveCurrentCustom {
    NSError *error=nil; if (![self ym_syncFieldsWithError:&error]) { [self ym_showError:error.localizedDescription]; return NO; } DirectColorTheme *old=self.editorState.selectedCustomTheme; if (!old) return NO;
    DirectColorTheme *theme=[self ym_themeFromCurrentNamed:old.name identifier:old.identifier created:old.createdAt error:&error]; if (!theme || ![self.store saveTheme:theme error:&error]) { [self ym_showError:error.localizedDescription]; return NO; }
    [self.store loadThemes:nil]; NSString *identifier=[@"custom:" stringByAppendingString:theme.identifier]; self.editorState=[[DirectColorThemeEditorState alloc] initWithBuiltInPresets:DirectColorThemeEditorState.builtInPresets customThemes:self.store.themes]; [self.editorState selectIdentifier:identifier]; [self ym_rebuildPopup]; [self ym_refreshControls]; self.statusLabel.stringValue=@"主题已保存"; return YES;
}

- (void)newTheme:(id)sender { (void)sender; [self ym_performCreationOperation:DirectColorThemeOperationNew]; }
- (void)duplicateTheme:(id)sender { (void)sender; [self ym_performCreationOperation:DirectColorThemeOperationDuplicate]; }
- (void)renameTheme:(id)sender { (void)sender; if (![self ym_resolveUnsavedForOperation:DirectColorThemeOperationRename]) return; DirectColorTheme *theme=self.editorState.selectedCustomTheme; if(!theme)return; NSString *name=[self ym_promptNameWithTitle:@"重命名自定义主题" defaultValue:theme.name]; if(!name)return; NSError *error=nil; DirectColorTheme *renamed=[self.store renameTheme:theme name:name error:&error]; if(!renamed){[self ym_showError:error.localizedDescription];return;} [self ym_reloadFromDisk]; [self.editorState selectIdentifier:[@"custom:" stringByAppendingString:renamed.identifier]]; [self ym_rebuildPopup]; [self ym_refreshControls]; }

- (void)deleteTheme:(id)sender {
    (void)sender; if (![self ym_resolveUnsavedForOperation:DirectColorThemeOperationDelete]) return; DirectColorTheme *theme=self.editorState.selectedCustomTheme; if(!theme)return;
    NSAlert *a=[[NSAlert alloc] init]; a.alertStyle=NSAlertStyleWarning; a.messageText=[NSString stringWithFormat:@"删除“%@”？",theme.name];
    NSDictionary *active=[self ym_readActiveConfiguration:nil]; BOOL applied=[active[@"custom_theme_id"] isKindOfClass:NSString.class]&&[active[@"custom_theme_id"] caseInsensitiveCompare:theme.identifier]==NSOrderedSame;
    a.informativeText=applied?@"此主题是上次应用源。删除后，微信仍使用最后应用快照，直到应用另一个主题。":@"此操作无法撤销。"; [a addButtonWithTitle:@"删除"]; [a addButtonWithTitle:@"取消"]; if([a runModal]!=NSAlertFirstButtonReturn)return;
    NSError *error=nil; if(![self.store deleteTheme:theme error:&error]){[self ym_showError:error.localizedDescription];return;} [self ym_reloadFromDisk]; if(applied)self.statusLabel.stringValue=@"源主题已删除；微信仍使用最后应用快照，直到应用另一个主题。";
}
- (void)reloadThemes:(id)sender { (void)sender; if([self ym_resolveUnsavedForOperation:DirectColorThemeOperationReload]) [self ym_reloadFromDisk]; }

- (void)closeWindow:(id)sender { (void)sender; [self.window performClose:nil]; }
- (BOOL)windowShouldClose:(NSWindow *)sender { (void)sender; if(self.allowingClose)return YES; return [self ym_resolveUnsavedForOperation:DirectColorThemeOperationClose]; }

- (void)applyAndRestart:(id)sender {
    (void)sender; NSError *error=nil; if(![self ym_syncFieldsWithError:&error]){[self ym_showError:error.localizedDescription];return;}
    DirectColorTheme *validation=[self ym_themeFromCurrentNamed:@"Validation" identifier:NSUUID.UUID.UUIDString created:nil error:&error]; if(!validation){[self ym_showError:error.localizedDescription];return;}
    if(self.editorState.isBuiltIn&&(self.editorState.dirty||self.editorState.requiresSaveAsForApply)){ if(![self ym_saveAsPrompted])return; validation=self.editorState.selectedCustomTheme; }
    if([self.editorState.selectedIdentifier hasPrefix:@"custom:"]&&!self.editorState.selectedCustomTheme){ [self ym_showError:@"上次应用的自定义主题源文件已不存在。请先使用“另存为自定义主题”保存当前快照，再应用。"]; return; }
    DirectColorTheme *custom=self.editorState.selectedCustomTheme;
    NSDictionary *config=nil;
    if(custom) {
        DirectColorThemeApplyResult *result=[DirectColorThemeApplyCoordinator prepareCustomApplicationForState:self.editorState sourceTheme:custom saveHandler:^BOOL(DirectColorTheme *theme, NSError **saveError) {
            return [self.store saveTheme:theme error:saveError];
        } reloadHandler:^NSArray<DirectColorTheme *> *(NSError **reloadError) {
            return [self.store loadThemes:reloadError];
        } error:&error];
        if(!result){[self ym_showError:error.localizedDescription];return;}
        custom=result.authoritativeTheme; config=result.applicationSnapshot;
        NSString *identifier=[@"custom:" stringByAppendingString:custom.identifier];
        self.editorState=[[DirectColorThemeEditorState alloc] initWithBuiltInPresets:DirectColorThemeEditorState.builtInPresets customThemes:self.store.themes];
        [self.editorState selectIdentifier:identifier]; [self ym_rebuildPopup]; [self ym_refreshControls];
    }
    NSString *runner=[[self ym_supportDirectory] stringByAppendingPathComponent:@"apply_theme.sh"]; if(![NSFileManager.defaultManager isExecutableFileAtPath:runner]){[self ym_showError:[NSString stringWithFormat:@"主题辅助程序不存在：%@\n请重新运行 Rely/install.sh。",runner]];return;}
    NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"应用全局主题？"; a.informativeText=@"微信将退出。主题表会从原始备份重新生成；有稳定配置的签名身份时将优先使用，然后自动启动微信。"; [a addButtonWithTitle:@"应用并重启"]; [a addButtonWithTitle:@"取消"]; if([a runModal]!=NSAlertFirstButtonReturn)return;
    if(!config) { NSString *key=[self.editorState.selectedIdentifier substringFromIndex:8]; config=@{@"preset":key,@"light":self.editorState.lightColors,@"dark":self.editorState.darkColors,@"advanced":self.editorState.advancedOverrides}; }
    NSString *dir=[self ym_supportDirectory]; if(![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]){[self ym_showError:error.localizedDescription];return;}
    NSData *json=[NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error]; NSString *path=[self ym_configPath]; if(!json||![json writeToFile:path options:NSDataWritingAtomic error:&error]){[self ym_showError:error.localizedDescription];return;}
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:YMCappuccinoThemeEnabledKey]; [NSUserDefaults.standardUserDefaults setObject:self.editorState.selectedIdentifier forKey:YMGlobalThemeSelectionKey]; [NSUserDefaults.standardUserDefaults synchronize];
    NSTask *task=[[NSTask alloc] init]; task.launchPath=@"/bin/bash"; task.arguments=@[@"-c",[NSString stringWithFormat:@"nohup %@ %@ >/tmp/SovietExtension-theme-apply.log 2>&1 </dev/null &",[self ym_shellQuote:runner],[self ym_shellQuote:path]]];
    @try{[task launch];[task waitUntilExit];}@catch(NSException *e){[self ym_showError:e.reason];return;} self.statusLabel.stringValue=@"正在应用主题并重启微信…"; if(self.applyHandler)self.applyHandler(YES); self.allowingClose=YES; [self.window close]; self.allowingClose=NO;
}

- (NSString *)ym_shellQuote:(NSString *)value { return [NSString stringWithFormat:@"'%@'",[value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }
- (void)ym_showError:(NSString *)message { self.statusLabel.stringValue=message?:@"未知错误"; NSAlert *a=[[NSAlert alloc] init]; a.alertStyle=NSAlertStyleCritical; a.messageText=@"主题操作失败"; a.informativeText=message?:@"未知错误"; [a runModal]; }

@end
