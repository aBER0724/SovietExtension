//
//  GlobalThemeSettingsWindowController.h
//  SovietExtension
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 全局主题设置：只读内置预设、命名自定义主题 CRUD、浅/深十项直色文本编辑与专家原始键覆盖。
/// 真正的 Qt/mmui 主题表在点击“应用并重启微信”后于下次启动生效。
@interface GlobalThemeSettingsWindowController : NSWindowController

@property (nonatomic, copy, nullable) void (^applyHandler)(BOOL success);

+ (void)registerDefaults;
- (void)showWindowCentered;

@end

NS_ASSUME_NONNULL_END
