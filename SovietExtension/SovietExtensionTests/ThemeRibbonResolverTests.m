#import <XCTest/XCTest.h>
#import "ThemeRibbonResolver.h"

@interface ThemeRibbonResolverTests : XCTestCase
@end

@implementation ThemeRibbonResolverTests

- (void)testSchema2SnapshotRibbonValuesAreAuthoritative {
    NSDictionary *config = @{
        @"schema_version": @2,
        @"preset": NSNull.null,
        @"light": @{ @"ribbon": @"#1234AB" },
        @"dark": @{ @"ribbon": @"#CDEF01" },
    };
    NSDictionary *fallbackLight = @{ @"ribbon": @"#AAAAAA" };
    NSDictionary *fallbackDark = @{ @"ribbon": @"#BBBBBB" };
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(config, NO, fallbackLight, fallbackDark), @"#1234AB");
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(config, YES, fallbackLight, fallbackDark), @"#CDEF01");
}

- (void)testLegacyPresetSnapshotRibbonValuesAreAuthoritative {
    NSDictionary *config = @{
        @"preset": @"gruvbox",
        @"light": @{ @"ribbon": @"#A1B2C3" },
        @"dark": @{ @"ribbon": @"#102030" },
    };
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(config, NO, @{}, @{}), @"#A1B2C3");
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(config, YES, @{}, @{}), @"#102030");
}

- (void)testMalformedOrMissingSnapshotFallsBackToDefaultsThenStaticColor {
    NSDictionary *config = @{ @"light": @{ @"ribbon": @"123456" }, @"dark": @{} };
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(config, NO, @{ @"ribbon": @"#ABCDEF" }, @{}), @"#ABCDEF");
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(config, YES, @{}, @{ @"ribbon": @"#bad" }), @"#11111B");
    XCTAssertEqualObjects(YMRibbonHexFromConfiguration(nil, NO, @{}, @{}), @"#DCE0E8");
}

- (void)testConfigurationFileCacheInvalidatesOnCreateReplaceAndDelete {
    YMThemeConfigurationFileCache *cache = [[YMThemeConfigurationFileCache alloc] init];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *path = [directory stringByAppendingPathComponent:@"theme.json"];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);

    XCTAssertNil([cache configurationAtPath:path]);
    XCTAssertTrue([@"{\"schema_version\":2,\"light\":{\"ribbon\":\"#112233\"}}" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    XCTAssertEqualObjects([cache configurationAtPath:path][@"light"][@"ribbon"], @"#112233");

    NSData *replacement = [@"{\"schema_version\":2,\"light\":{\"ribbon\":\"#ABCDEF\"},\"padding\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([replacement writeToFile:path options:NSDataWritingAtomic error:nil]);
    XCTAssertEqualObjects([cache configurationAtPath:path][@"light"][@"ribbon"], @"#ABCDEF");

    XCTAssertTrue([NSFileManager.defaultManager removeItemAtPath:path error:nil]);
    XCTAssertNil([cache configurationAtPath:path]);
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
}

- (void)testConfigurationFileCacheIsSafeForConcurrentReads {
    YMThemeConfigurationFileCache *cache = [[YMThemeConfigurationFileCache alloc] init];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *path = [directory stringByAppendingPathComponent:@"theme.json"];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
    XCTAssertTrue([@"{\"schema_version\":2,\"dark\":{\"ribbon\":\"#102030\"}}" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    dispatch_apply(100, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
        (void)index;
        XCTAssertEqualObjects([cache configurationAtPath:path][@"dark"][@"ribbon"], @"#102030");
    });
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
}

@end
