#import "DirectColorThemeStore.h"

NSErrorDomain const DirectColorThemeStoreErrorDomain = @"DirectColorThemeStoreErrorDomain";

static NSError *StoreError(DirectColorThemeStoreErrorCode code, NSString *description, NSError *underlying) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey:description} mutableCopy];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:DirectColorThemeStoreErrorDomain code:code userInfo:info];
}

@interface DirectColorTheme (StoreAccess)
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSDate *createdAt;
@property (nonatomic, copy, readwrite) NSDate *updatedAt;
@property (nonatomic, copy, readwrite) NSDictionary *lightColors;
@property (nonatomic, copy, readwrite) NSDictionary *darkColors;
@property (nonatomic, copy, readwrite) NSDictionary *advancedOverrides;
@property (nonatomic, copy) NSURL *sourceURL;
@end

@interface DirectColorThemeStore ()
@property (nonatomic, copy, readwrite) NSURL *directoryURL;
@property (nonatomic, copy, readwrite) NSArray<DirectColorTheme *> *themes;
@property (nonatomic, copy, readwrite) NSArray<NSError *> *errors;
@end

@implementation DirectColorThemeStore

- (instancetype)init {
    NSURL *support = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                            inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    return [self initWithDirectoryURL:[[support URLByAppendingPathComponent:@"SovietExtension" isDirectory:YES]
                                      URLByAppendingPathComponent:@"themes" isDirectory:YES]];
}

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL {
    self = [super init];
    if (self) {
        _directoryURL = [directoryURL copy];
        _themes = @[];
        _errors = @[];
    }
    return self;
}

- (NSArray<DirectColorTheme *> *)sortedThemes:(NSArray<DirectColorTheme *> *)themes {
    return [themes sortedArrayUsingComparator:^NSComparisonResult(DirectColorTheme *a, DirectColorTheme *b) {
        NSComparisonResult byName = [a.name caseInsensitiveCompare:b.name];
        return byName == NSOrderedSame ? [a.identifier compare:b.identifier] : byName;
    }];
}

- (BOOL)ensureDirectory:(NSError **)error {
    NSError *underlying = nil;
    if ([[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions:@0700} error:&underlying]) return YES;
    if (error) *error = StoreError(DirectColorThemeStoreErrorIO, @"Could not create the themes directory.", underlying);
    return NO;
}

- (NSArray<DirectColorTheme *> *)loadThemes:(NSError **)error {
    if (![self ensureDirectory:error]) return self.themes;
    NSError *listError = nil;
    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.directoryURL
                                      includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&listError];
    if (!files) {
        if (error) *error = StoreError(DirectColorThemeStoreErrorIO, @"Could not list theme documents.", listError);
        return self.themes;
    }
    NSMutableArray *loaded = [NSMutableArray array];
    NSMutableArray *loadErrors = [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    for (NSURL *url in [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent compare:b.lastPathComponent]; }]) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSError *underlying = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&underlying];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&underlying] : nil;
        DirectColorTheme *theme = json ? [DirectColorTheme themeFromDictionary:json error:&underlying] : nil;
        NSString *foldedName = theme.name.lowercaseString;
        if (theme && [names containsObject:foldedName]) {
            underlying = StoreError(DirectColorThemeStoreErrorDuplicateName,
                                    [NSString stringWithFormat:@"Theme %@ duplicates another name.", url.lastPathComponent], nil);
            theme = nil;
        }
        if (!theme) {
            NSString *description = [NSString stringWithFormat:@"Could not load %@: %@", url.lastPathComponent,
                                     underlying.localizedDescription ?: @"invalid document"];
            [loadErrors addObject:StoreError(DirectColorThemeStoreErrorIO, description, underlying)];
            continue;
        }
        theme.sourceURL = url;
        [names addObject:foldedName];
        [loaded addObject:theme];
    }
    self.themes = [self sortedThemes:loaded];
    self.errors = loadErrors;
    return self.themes;
}

- (DirectColorTheme *)themeWithIdentifier:(NSString *)identifier {
    NSString *canonical = [[NSUUID alloc] initWithUUIDString:identifier].UUIDString.uppercaseString;
    if (!canonical) return nil;
    for (DirectColorTheme *theme in self.themes) if ([theme.identifier isEqualToString:canonical]) return theme;
    return nil;
}

- (NSString *)normalizedName:(NSString *)name error:(NSError **)error excludingID:(NSString *)identifier {
    NSString *trimmed = [name isKindOfClass:NSString.class] ? [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (trimmed.length == 0) {
        if (error) *error = StoreError(DirectColorThemeStoreErrorInvalidName, @"Theme name cannot be empty.", nil);
        return nil;
    }
    for (DirectColorTheme *theme in self.themes) {
        if (![theme.identifier isEqualToString:identifier] && [theme.name caseInsensitiveCompare:trimmed] == NSOrderedSame) {
            if (error) *error = StoreError(DirectColorThemeStoreErrorDuplicateName, @"A theme with this name already exists.", nil);
            return nil;
        }
    }
    return trimmed;
}

- (DirectColorTheme *)themeWithID:(NSString *)identifier name:(NSString *)name created:(NSDate *)created
                          updated:(NSDate *)updated light:(NSDictionary *)light dark:(NSDictionary *)dark advanced:(NSDictionary *)advanced
                            error:(NSError **)error {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDictionary *document = @{@"schema_version":@1, @"id":identifier, @"name":name, @"source":@"custom",
        @"created_at":[formatter stringFromDate:created], @"updated_at":[formatter stringFromDate:updated],
        @"light":light, @"dark":dark, @"advanced":advanced ?: @{@"light":@{}, @"dark":@{}}};
    return [DirectColorTheme themeFromDictionary:document error:error];
}

- (DirectColorTheme *)createThemeNamed:(NSString *)name lightColors:(NSDictionary *)lightColors
                            darkColors:(NSDictionary *)darkColors error:(NSError **)error {
    NSString *validName = [self normalizedName:name error:error excludingID:nil];
    if (!validName) return nil;
    NSDate *now = [NSDate date];
    DirectColorTheme *theme = [self themeWithID:NSUUID.UUID.UUIDString.uppercaseString name:validName created:now updated:now
                                           light:lightColors dark:darkColors advanced:nil error:error];
    if (!theme || ![self saveTheme:theme error:error]) return nil;
    return theme;
}

- (DirectColorTheme *)duplicateTheme:(DirectColorTheme *)theme name:(NSString *)name error:(NSError **)error {
    NSString *validName = [self normalizedName:name error:error excludingID:nil];
    if (!validName) return nil;
    NSDate *now = [NSDate date];
    if ([now compare:theme.createdAt] != NSOrderedDescending) {
        now = [theme.createdAt dateByAddingTimeInterval:0.001];
    }
    DirectColorTheme *copy = [self themeWithID:NSUUID.UUID.UUIDString.uppercaseString name:validName created:now updated:now
                                          light:theme.lightColors dark:theme.darkColors advanced:theme.advancedOverrides error:error];
    if (!copy || ![self saveTheme:copy error:error]) return nil;
    return copy;
}

- (DirectColorTheme *)renameTheme:(DirectColorTheme *)theme name:(NSString *)name error:(NSError **)error {
    NSString *validName = [self normalizedName:name error:error excludingID:theme.identifier];
    if (!validName) return nil;
    DirectColorTheme *renamed = [self themeWithID:theme.identifier name:validName created:theme.createdAt updated:[NSDate date]
                                             light:theme.lightColors dark:theme.darkColors advanced:theme.advancedOverrides error:error];
    renamed.sourceURL = theme.sourceURL;
    if (!renamed || ![self saveTheme:renamed error:error]) return nil;
    return renamed;
}

- (BOOL)saveTheme:(DirectColorTheme *)theme error:(NSError **)error {
    NSString *validName = [self normalizedName:theme.name error:error excludingID:theme.identifier];
    if (!validName || ![self ensureDirectory:error]) return NO;
    NSError *underlying = nil;
    NSDate *updatedAt = [NSDate date];
    if ([updatedAt compare:theme.updatedAt] != NSOrderedDescending) {
        updatedAt = [theme.updatedAt dateByAddingTimeInterval:0.001];
    }
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSMutableDictionary *document = [theme.dictionaryRepresentation mutableCopy];
    document[@"updated_at"] = [formatter stringFromDate:updatedAt];
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted error:&underlying];
    NSURL *canonicalURL = [self.directoryURL URLByAppendingPathComponent:[theme.identifier.uppercaseString stringByAppendingPathExtension:@"json"]];
    if (!data || ![data writeToURL:canonicalURL options:NSDataWritingAtomic error:&underlying]) {
        if (error) *error = StoreError(DirectColorThemeStoreErrorIO, @"Could not save the theme document atomically.", underlying);
        return NO;
    }
    NSURL *oldURL = theme.sourceURL;
    if (oldURL && ![oldURL.URLByStandardizingPath isEqual:canonicalURL.URLByStandardizingPath]) {
        if (![[NSFileManager defaultManager] removeItemAtURL:oldURL error:&underlying]) {
            if (error) *error = StoreError(DirectColorThemeStoreErrorIO, @"Saved the canonical document but could not remove its old filename.", underlying);
            return NO;
        }
    }
    theme.updatedAt = updatedAt;
    theme.sourceURL = canonicalURL;
    NSMutableArray *updated = [self.themes mutableCopy];
    NSUInteger index = [updated indexOfObjectPassingTest:^BOOL(DirectColorTheme *item, NSUInteger idx, BOOL *stop) {
        return [item.identifier isEqualToString:theme.identifier];
    }];
    if (index == NSNotFound) [updated addObject:theme]; else updated[index] = theme;
    self.themes = [self sortedThemes:updated];
    return YES;
}

- (BOOL)deleteTheme:(DirectColorTheme *)theme error:(NSError **)error {
    NSURL *url = theme.sourceURL ?: [self.directoryURL URLByAppendingPathComponent:[theme.identifier stringByAppendingPathExtension:@"json"]];
    NSError *underlying = nil;
    if (![[NSFileManager defaultManager] removeItemAtURL:url error:&underlying]) {
        if (error) *error = StoreError(DirectColorThemeStoreErrorIO, @"Could not delete the theme document.", underlying);
        return NO;
    }
    self.themes = [self.themes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DirectColorTheme *item, NSDictionary *bindings) {
        return ![item.identifier isEqualToString:theme.identifier];
    }]];
    return YES;
}

@end
