#import <XCTest/XCTest.h>
#import "DirectColorTheme.h"
#import "DirectColorThemeStore.h"

@interface DirectColorThemeStoreTests : XCTestCase
@property (nonatomic, strong) NSURL *directoryURL;
@property (nonatomic, strong) DirectColorThemeStore *store;
@end

@implementation DirectColorThemeStoreTests

- (void)setUp {
    [super setUp];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    self.directoryURL = [NSURL fileURLWithPath:path isDirectory:YES];
    self.store = [[DirectColorThemeStore alloc] initWithDirectoryURL:self.directoryURL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0700}
                                     ofItemAtPath:self.directoryURL.path error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.directoryURL error:nil];
    [super tearDown];
}

- (NSDictionary<NSString *, NSString *> *)colorsWithLowercaseValues {
    return @{
        @"base": @"#aabbcc", @"sidebar": @"#010203", @"ribbon": @"#111213",
        @"outgoing_bubble": @"#212223", @"incoming_bubble": @"#313233",
        @"text": @"#414243", @"subtext": @"#515253", @"accent": @"#616263",
        @"link": @"#717273", @"danger": @"#818283"
    };
}

- (NSDictionary<NSString *, NSString *> *)otherColors {
    return @{
        @"base": @"#ABCDEF", @"sidebar": @"#020304", @"ribbon": @"#121314",
        @"outgoing_bubble": @"#222324", @"incoming_bubble": @"#323334",
        @"text": @"#424344", @"subtext": @"#525354", @"accent": @"#626364",
        @"link": @"#727374", @"danger": @"#828384"
    };
}

- (NSMutableDictionary *)validSchemaOneDocumentNamed:(NSString *)name {
    return [@{@"schema_version":@1, @"id":[NSUUID UUID].UUIDString,
        @"name":name, @"source":@"custom", @"created_at":@"2024-01-01T00:00:00Z",
        @"updated_at":@"2024-01-01T00:00:00Z", @"light":[self colorsWithLowercaseValues],
        @"dark":[self otherColors], @"advanced":@{@"light":@{}, @"dark":@{}}} mutableCopy];
}

- (NSMutableDictionary *)validSchemaZeroDocumentNamed:(NSString *)name {
    return [@{@"id":[NSUUID UUID].UUIDString, @"name":name,
        @"created_at":@"2024-01-01T00:00:00Z", @"updated_at":@"2024-01-01T00:00:00Z",
        @"light":[self colorsWithLowercaseValues], @"dark":[self otherColors]} mutableCopy];
}

- (DirectColorTheme *)createNamed:(NSString *)name error:(NSError **)error {
    return [self.store createThemeNamed:name
                            lightColors:[self colorsWithLowercaseValues]
                             darkColors:[self otherColors]
                                  error:error];
}

- (void)testCreateSaveReloadTwoNamedThemesAndCanonicalJSON {
    NSError *error = nil;
    DirectColorTheme *zulu = [self createNamed:@"  Zulu  " error:&error];
    XCTAssertNotNil(zulu); XCTAssertNil(error);
    DirectColorTheme *alpha = [self createNamed:@"Alpha" error:&error];
    XCTAssertNotNil(alpha); XCTAssertNil(error);
    XCTAssertEqualObjects(zulu.name, @"Zulu");
    XCTAssertEqualObjects(zulu.lightColors[@"base"], @"#AABBCC");

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.directoryURL.path error:&error];
    XCTAssertEqual(files.count, 2u);
    NSString *canonical = [zulu.identifier stringByAppendingPathExtension:@"json"];
    XCTAssertTrue([files containsObject:canonical]);
    XCTAssertEqualObjects(zulu.identifier, zulu.identifier.uppercaseString);

    NSData *data = [NSData dataWithContentsOfURL:[self.directoryURL URLByAppendingPathComponent:canonical]];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertEqualObjects(json[@"schema_version"], @1);
    XCTAssertEqualObjects(json[@"source"], @"custom");

    DirectColorThemeStore *reloaded = [[DirectColorThemeStore alloc] initWithDirectoryURL:self.directoryURL];
    NSArray *themes = [reloaded loadThemes:&error];
    XCTAssertNil(error);
    XCTAssertEqual(themes.count, 2u);
    XCTAssertEqualObjects([themes valueForKey:@"name"], (@[@"Alpha", @"Zulu"]));
    XCTAssertEqualObjects([reloaded themeWithIdentifier:zulu.identifier.lowercaseString].identifier, zulu.identifier);
}

- (void)testRejectsMissingExtraAndMalformedDirectColorsAndInvalidAdvanced {
    NSError *error = nil;
    NSMutableDictionary *missing = [[self colorsWithLowercaseValues] mutableCopy];
    [missing removeObjectForKey:@"base"];
    XCTAssertNil([self.store createThemeNamed:@"Missing" lightColors:missing darkColors:[self otherColors] error:&error]);
    XCTAssertNotNil(error);

    NSMutableDictionary *extra = [[self colorsWithLowercaseValues] mutableCopy];
    extra[@"semantic_background"] = @"#FFFFFF";
    error = nil;
    XCTAssertNil([self.store createThemeNamed:@"Extra" lightColors:extra darkColors:[self otherColors] error:&error]);

    NSMutableDictionary *malformed = [[self colorsWithLowercaseValues] mutableCopy];
    malformed[@"base"] = @"rgb(1,2,3)";
    error = nil;
    XCTAssertNil([self.store createThemeNamed:@"Bad" lightColors:malformed darkColors:[self otherColors] error:&error]);

    NSDictionary *document = @{@"schema_version":@1, @"id":[NSUUID UUID].UUIDString,
        @"name":@"Advanced", @"source":@"custom", @"created_at":@"2024-01-01T00:00:00Z",
        @"updated_at":@"2024-01-01T00:00:00Z", @"light":[self colorsWithLowercaseValues],
        @"dark":[self otherColors], @"advanced":@{@"light":@{@"":@"#FFFFFF"}, @"dark":@{}}};
    XCTAssertNil([DirectColorTheme themeFromDictionary:document error:&error]);
}

- (void)testRejectsUnknownTopLevelFieldsForSchemaZeroAndOne {
    NSArray<NSString *> *unknownKeys = @[@"palette", @"editor_mode", @"generated", @"derived", @"udpated_at"];
    for (NSNumber *schemaVersion in @[@0, @1]) {
        for (NSString *unknownKey in unknownKeys) {
            NSMutableDictionary *document = [schemaVersion isEqual:@1]
                ? [self validSchemaOneDocumentNamed:@"Strict"]
                : [self validSchemaZeroDocumentNamed:@"Strict"];
            document[unknownKey] = @{};
            NSError *error = nil;
            XCTAssertNil([DirectColorTheme themeFromDictionary:document error:&error],
                         @"schema %@ accepted unknown key %@", schemaVersion, unknownKey);
            XCTAssertNotNil(error);
        }
    }

    NSError *error = nil;
    NSMutableDictionary *legacyWithAdvanced = [self validSchemaZeroDocumentNamed:@"Legacy Advanced"];
    legacyWithAdvanced[@"advanced"] = @{@"light":@{}, @"dark":@{}};
    XCTAssertNotNil([DirectColorTheme themeFromDictionary:legacyWithAdvanced error:&error]);
    XCTAssertNil(error);
}

- (void)testSchemaVersionRequiresNonBooleanNumberExactlyEqualToOne {
    NSArray *invalidVersions = @[@1.5, @"1", @YES, @NO, @0, @2];
    for (id version in invalidVersions) {
        NSMutableDictionary *document = [self validSchemaOneDocumentNamed:@"Version"];
        document[@"schema_version"] = version;
        NSError *error = nil;
        XCTAssertNil([DirectColorTheme themeFromDictionary:document error:&error],
                     @"accepted invalid schema_version %@ (%@)", version, [version class]);
        XCTAssertNotNil(error);
    }

    NSError *error = nil;
    NSMutableDictionary *integralDouble = [self validSchemaOneDocumentNamed:@"Version"];
    integralDouble[@"schema_version"] = @1.0;
    XCTAssertNotNil([DirectColorTheme themeFromDictionary:integralDouble error:&error]);
    XCTAssertNil(error);
}

- (void)testUnicodeCanonicalAndLocaleStableNameUniquenessForLoadAndCRUD {
    NSError *error = nil;
    NSString *composed = @"Caf\u00E9 \u00C5NGSTR\u00D6M";
    NSString *decomposedCaseVariant = @"CAFE\u0301 a\u030Angstro\u0308m";
    XCTAssertNotNil([self createNamed:composed error:&error]);
    XCTAssertNil([self createNamed:decomposedCaseVariant error:&error]);
    XCTAssertEqual(error.code, DirectColorThemeStoreErrorDuplicateName);

    DirectColorThemeStore *writer = [[DirectColorThemeStore alloc] initWithDirectoryURL:self.directoryURL];
    NSMutableDictionary *duplicate = [self validSchemaOneDocumentNamed:decomposedCaseVariant];
    error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:duplicate options:0 error:&error];
    NSURL *duplicateURL = [self.directoryURL URLByAppendingPathComponent:@"unicode-duplicate.json"];
    XCTAssertTrue([data writeToURL:duplicateURL options:NSDataWritingAtomic error:&error]);

    NSArray *loaded = [writer loadThemes:&error];
    XCTAssertNil(error);
    XCTAssertEqual(loaded.count, 1u);
    XCTAssertEqual(writer.errors.count, 1u);
}

- (void)testDuplicateNameRejectedCaseInsensitively {
    NSError *error = nil;
    XCTAssertNotNil([self createNamed:@"Ocean" error:&error]);
    XCTAssertNil([self createNamed:@" ocean " error:&error]);
    XCTAssertEqual(error.code, DirectColorThemeStoreErrorDuplicateName);
}

- (void)testDuplicateRenameDeleteCRUDAndSorting {
    NSError *error = nil;
    DirectColorTheme *beta = [self createNamed:@"beta" error:&error];
    DirectColorTheme *alpha2 = [self createNamed:@"alpha" error:&error];
    DirectColorTheme *alpha1 = [self createNamed:@"Alpha 2" error:&error];
    XCTAssertEqualObjects([self.store.themes valueForKey:@"name"], (@[@"alpha", @"Alpha 2", @"beta"]));

    DirectColorTheme *copy = [self.store duplicateTheme:beta name:@"Copy" error:&error];
    XCTAssertNotEqualObjects(copy.identifier, beta.identifier);
    XCTAssertNotEqualObjects(copy.createdAt, beta.createdAt);
    XCTAssertEqualObjects(copy.lightColors, beta.lightColors);

    DirectColorTheme *renamed = [self.store renameTheme:copy name:@"Gamma" error:&error];
    XCTAssertEqualObjects(renamed.name, @"Gamma");
    XCTAssertEqualObjects(renamed.identifier, copy.identifier);
    XCTAssertEqualObjects(renamed.createdAt, copy.createdAt);
    XCTAssertTrue([renamed.updatedAt compare:copy.updatedAt] != NSOrderedAscending);
    XCTAssertTrue([self.store deleteTheme:renamed error:&error]);
    XCTAssertNil([self.store themeWithIdentifier:renamed.identifier]);
    XCTAssertNotNil(alpha1); XCTAssertNotNil(alpha2);
}

- (void)testCorruptSiblingIsolationReportsError {
    NSError *error = nil;
    [self createNamed:@"Valid" error:&error];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    [@"not json" writeToURL:[self.directoryURL URLByAppendingPathComponent:@"broken.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    DirectColorThemeStore *reloaded = [[DirectColorThemeStore alloc] initWithDirectoryURL:self.directoryURL];
    NSArray *themes = [reloaded loadThemes:&error];
    XCTAssertEqual(themes.count, 1u);
    XCTAssertNil(error);
    XCTAssertEqual(reloaded.errors.count, 1u);
    XCTAssertTrue([reloaded.errors.firstObject.localizedDescription containsString:@"broken.json"]);
}

- (void)testSchemaZeroMigrationDoesNotRewriteUntilCanonicalSave {
    NSError *error = nil;
    NSString *identifier = [NSUUID UUID].UUIDString.lowercaseString;
    NSDictionary *legacy = @{@"id":identifier, @"name":@"Legacy",
        @"created_at":@"2024-01-01T00:00:00Z", @"updated_at":@"2024-01-02T00:00:00Z",
        @"light":[self colorsWithLowercaseValues], @"dark":[self otherColors]};
    NSData *original = [NSJSONSerialization dataWithJSONObject:legacy options:NSJSONWritingPrettyPrinted error:&error];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL withIntermediateDirectories:YES attributes:nil error:&error];
    NSURL *oldURL = [self.directoryURL URLByAppendingPathComponent:@"old-name.json"];
    XCTAssertTrue([original writeToURL:oldURL options:0 error:&error]);

    [self.store loadThemes:&error];
    DirectColorTheme *theme = self.store.themes.firstObject;
    XCTAssertEqualObjects(theme.identifier, identifier.uppercaseString);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:oldURL], original);
    XCTAssertTrue([self.store saveTheme:theme error:&error]);
    NSURL *canonicalURL = [self.directoryURL URLByAppendingPathComponent:[theme.identifier stringByAppendingPathExtension:@"json"]];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:canonicalURL.path]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:oldURL.path]);
}

- (void)testAtomicWriteFailurePreservesOldDocument {
    NSError *error = nil;
    DirectColorTheme *theme = [self createNamed:@"Original" error:&error];
    NSURL *fileURL = [self.directoryURL URLByAppendingPathComponent:[theme.identifier stringByAppendingPathExtension:@"json"]];
    NSData *before = [NSData dataWithContentsOfURL:fileURL];
    XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0500}
                                                          ofItemAtPath:self.directoryURL.path error:&error]);
    DirectColorTheme *renamed = [self.store renameTheme:theme name:@"Changed" error:&error];
    XCTAssertNil(renamed);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:fileURL], before);
}

- (void)testSchemaOneRequiresCustomSourceAndAdvancedContainer {
    NSMutableDictionary *document = [@{@"schema_version":@1, @"id":[NSUUID UUID].UUIDString,
        @"name":@"Schema One", @"source":@"preset", @"created_at":@"2024-01-01T00:00:00Z",
        @"updated_at":@"2024-01-01T00:00:00Z", @"light":[self colorsWithLowercaseValues],
        @"dark":[self otherColors], @"advanced":@{@"light":@{}, @"dark":@{}}} mutableCopy];
    NSError *error = nil;
    XCTAssertNil([DirectColorTheme themeFromDictionary:document error:&error]);
    XCTAssertNotNil(error);

    document[@"source"] = @"custom";
    [document removeObjectForKey:@"advanced"];
    error = nil;
    XCTAssertNil([DirectColorTheme themeFromDictionary:document error:&error]);
    XCTAssertNotNil(error);
}

- (void)testAdvancedOverrideDictionariesAreImmutable {
    NSDictionary *document = @{@"schema_version":@1, @"id":[NSUUID UUID].UUIDString,
        @"name":@"Immutable", @"source":@"custom", @"created_at":@"2024-01-01T00:00:00Z",
        @"updated_at":@"2024-01-01T00:00:00Z", @"light":[self colorsWithLowercaseValues],
        @"dark":[self otherColors], @"advanced":@{@"light":@{@"SomeKey":@"#aabbcc"}, @"dark":@{}}};
    NSError *error = nil;
    DirectColorTheme *theme = [DirectColorTheme themeFromDictionary:document error:&error];
    XCTAssertNotNil(theme);
    XCTAssertNil(error);
    XCTAssertThrows([(NSMutableDictionary *)theme.advancedOverrides[@"light"] setObject:@"#FFFFFF" forKey:@"SomeKey"]);
    XCTAssertEqualObjects(theme.advancedOverrides[@"light"][@"SomeKey"], @"#AABBCC");
}

- (void)testApplicationSnapshotContainsOnlyDirectSchemaTwoData {
    NSError *error = nil;
    DirectColorTheme *theme = [self createNamed:@"Snapshot" error:&error];
    NSDictionary *snapshot = [theme applicationSnapshot];
    NSSet *expectedKeys = [NSSet setWithArray:@[@"schema_version", @"preset", @"custom_theme_id", @"light", @"dark", @"advanced"]];
    XCTAssertEqualObjects([NSSet setWithArray:snapshot.allKeys], expectedKeys);
    XCTAssertEqualObjects(snapshot[@"schema_version"], @2);
    XCTAssertEqualObjects(snapshot[@"preset"], NSNull.null);
    XCTAssertEqualObjects(snapshot[@"custom_theme_id"], theme.identifier);
    XCTAssertEqual([snapshot[@"light"] count], 10u);
    XCTAssertEqual([snapshot[@"dark"] count], 10u);
    XCTAssertNil(snapshot[@"palette"]);
    XCTAssertNil(snapshot[@"name"]);
}

@end
