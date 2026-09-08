#import "ThemeRibbonResolver.h"

static BOOL YMIsStrictRibbonHex(id value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *string = value;
    if (string.length != 7 || ![string hasPrefix:@"#"]) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [[string substringFromIndex:1] rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound;
}

NSString *YMRibbonHexFromConfiguration(NSDictionary *configuration,
                                       BOOL dark,
                                       NSDictionary *fallbackLightColors,
                                       NSDictionary *fallbackDarkColors) {
    BOOL schemaTwo = [configuration[@"schema_version"] isKindOfClass:NSNumber.class] &&
                     [configuration[@"schema_version"] integerValue] == 2;
    BOOL legacyPreset = [configuration[@"preset"] isKindOfClass:NSString.class];
    NSString *side = dark ? @"dark" : @"light";
    id snapshotColors = (schemaTwo || legacyPreset) ? configuration[side] : nil;
    id snapshotRibbon = [snapshotColors isKindOfClass:NSDictionary.class] ? snapshotColors[@"ribbon"] : nil;
    if (YMIsStrictRibbonHex(snapshotRibbon)) return snapshotRibbon;

    NSDictionary *fallback = dark ? fallbackDarkColors : fallbackLightColors;
    id fallbackRibbon = [fallback isKindOfClass:NSDictionary.class] ? fallback[@"ribbon"] : nil;
    if (YMIsStrictRibbonHex(fallbackRibbon)) return fallbackRibbon;
    return dark ? @"#11111B" : @"#DCE0E8";
}
