//
//  CappuccinoPatch.h
//  SovietExtension
//
//  微信 4.x Qt 主题色表运行时补丁：将聊天气泡替换为卡布奇诺配色。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults 开关。修改后需重启微信，确保 Qt 已缓存的颜色全部重新加载。
FOUNDATION_EXPORT NSString * const YMCappuccinoThemeEnabledKey;

/// 注册默认值；默认关闭，用户可从「苏维埃助手 → 主题模式」开启。
FOUNDATION_EXPORT void YMRegisterCappuccinoThemeDefaults(void);

/// 安装 dyld 监听，并在 wechat.dylib 加载后修改其 __DATA_CONST 主题色表。
FOUNDATION_EXPORT void YMInstallCappuccinoThemePatch(void);

NS_ASSUME_NONNULL_END
