//
//  GlobalThemeSettingsWindowController.h
//  SovietExtension
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 全局主题设置：预设选择、核心语义色覆盖、完整 named-key JSON 覆盖和实时预览。
/// 真正的 Qt/mmui 主题表在点击“应用并重启微信”后于下次启动生效。
@interface GlobalThemeSettingsWindowController : NSWindowController

@property (nonatomic, copy, nullable) void (^applyHandler)(BOOL success);

+ (void)registerDefaults;
- (void)showWindowCentered;

@end

NS_ASSUME_NONNULL_END
