#import "ThemeRibbonResolver.h"

@interface YMThemeConfigurationFileCache ()
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, copy, nullable) NSString *cachedPath;
@property(nonatomic, strong, nullable) NSDictionary *cachedConfiguration;
@property(nonatomic) unsigned long long cachedSize;
@property(nonatomic) NSTimeInterval cachedModificationTime;
@property(nonatomic) BOOL hasSnapshot;
@end

@implementation YMThemeConfigurationFileCache

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (NSDictionary *)configurationAtPath:(NSString *)path {
    [self.lock lock];
    @try {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        unsigned long long size = attributes ? [attributes fileSize] : ULLONG_MAX;
        NSTimeInterval modificationTime = attributes ? [attributes fileModificationDate].timeIntervalSince1970 : -1;
        if (self.hasSnapshot && [self.cachedPath isEqualToString:path] &&
            self.cachedSize == size && self.cachedModificationTime == modificationTime) {
            return self.cachedConfiguration;
        }

        NSData *data = [NSData dataWithContentsOfFile:path];
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        self.cachedPath = [path copy];
        self.cachedSize = size;
        self.cachedModificationTime = modificationTime;
        self.cachedConfiguration = [object isKindOfClass:NSDictionary.class] ? object : nil;
        self.hasSnapshot = YES;
        return self.cachedConfiguration;
    } @finally {
        [self.lock unlock];
    }
}

@end

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
