#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns a strict #RRGGBB ribbon value. The active file configuration wins,
/// then the matching UserDefaults dictionary, then the built-in static color.
FOUNDATION_EXPORT NSString *YMRibbonHexFromConfiguration(
    NSDictionary * _Nullable configuration,
    BOOL dark,
    NSDictionary * _Nullable fallbackLightColors,
    NSDictionary * _Nullable fallbackDarkColors);

NS_ASSUME_NONNULL_END
