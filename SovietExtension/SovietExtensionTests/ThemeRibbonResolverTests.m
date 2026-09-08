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

@end
