#import "DirectColorTheme.h"

NSErrorDomain const DirectColorThemeErrorDomain = @"DirectColorThemeErrorDomain";

static NSError *ThemeError(DirectColorThemeErrorCode code, NSString *description) {
    return [NSError errorWithDomain:DirectColorThemeErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSDateFormatter *ThemeDateFormatter(void) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return formatter;
}

static NSDate *ParseDate(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSDate *date = [ThemeDateFormatter() dateFromString:value];
    if (date) return date;
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    return [iso dateFromString:value];
}

static NSString *FormatDate(NSDate *date) {
    return [ThemeDateFormatter() stringFromDate:date];
}

static NSDictionary *NormalizeColors(id value, BOOL exactDirectKeys, NSError **error) {
    if (![value isKindOfClass:NSDictionary.class]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidColors, @"Colors must be a dictionary.");
        return nil;
    }
    NSDictionary *colors = value;
    if (exactDirectKeys && ![[NSSet setWithArray:colors.allKeys] isEqualToSet:DirectColorTheme.requiredColorKeys]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidColors, @"Direct colors must contain exactly the ten required keys.");
        return nil;
    }
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^#[0-9A-Fa-f]{6}$" options:0 error:nil];
    NSMutableDictionary *normalized = [NSMutableDictionary dictionaryWithCapacity:colors.count];
    for (id key in colors) {
        id color = colors[key];
        if (![key isKindOfClass:NSString.class] || [key length] == 0 || ![color isKindOfClass:NSString.class] ||
            [regex numberOfMatchesInString:color options:0 range:NSMakeRange(0, [color length])] != 1) {
            if (error) *error = ThemeError(exactDirectKeys ? DirectColorThemeErrorInvalidColors : DirectColorThemeErrorInvalidAdvancedOverrides,
                                           @"Color keys must be nonempty strings and values must use #RRGGBB.");
            return nil;
        }
        normalized[key] = [color uppercaseString];
    }
    return [normalized copy];
}

@interface DirectColorTheme ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSDate *createdAt;
@property (nonatomic, copy, readwrite) NSDate *updatedAt;
@property (nonatomic, copy, readwrite) NSDictionary *lightColors;
@property (nonatomic, copy, readwrite) NSDictionary *darkColors;
@property (nonatomic, copy, readwrite) NSDictionary *advancedOverrides;
@property (nonatomic, copy) NSURL *sourceURL;
@end

@implementation DirectColorTheme

+ (NSSet<NSString *> *)requiredColorKeys {
    static NSSet *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[@"base", @"sidebar", @"ribbon", @"outgoing_bubble",
            @"incoming_bubble", @"text", @"subtext", @"accent", @"link", @"danger"]];
    });
    return keys;
}

+ (instancetype)themeFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidDocument, @"Theme document must be a JSON object.");
        return nil;
    }
    id schema = dictionary[@"schema_version"];
    BOOL legacy = (schema == nil);
    BOOL schemaIsBoolean = schema && CFGetTypeID((__bridge CFTypeRef)schema) == CFBooleanGetTypeID();
    if (schema && (![schema isKindOfClass:NSNumber.class] || schemaIsBoolean || [schema doubleValue] != 1.0)) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidDocument, @"Unsupported theme schema version.");
        return nil;
    }
    NSSet *documentKeys = [NSSet setWithArray:dictionary.allKeys];
    NSSet *allowedKeys = legacy
        ? [NSSet setWithArray:@[@"id", @"name", @"created_at", @"updated_at", @"light", @"dark", @"advanced"]]
        : [NSSet setWithArray:@[@"schema_version", @"id", @"name", @"source", @"created_at", @"updated_at", @"light", @"dark", @"advanced"]];
    NSSet *requiredKeys = legacy
        ? [NSSet setWithArray:@[@"id", @"name", @"created_at", @"updated_at", @"light", @"dark"]]
        : allowedKeys;
    if (![documentKeys isSubsetOfSet:allowedKeys] || ![requiredKeys isSubsetOfSet:documentKeys]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidDocument, @"Theme document contains missing or unknown top-level fields.");
        return nil;
    }
    if (!legacy && ![dictionary[@"source"] isKindOfClass:NSString.class]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidDocument, @"Theme source must be custom.");
        return nil;
    }
    if (!legacy && ![dictionary[@"source"] isEqualToString:@"custom"]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidDocument, @"Theme source must be custom.");
        return nil;
    }
    NSString *rawID = dictionary[@"id"];
    NSUUID *uuid = [rawID isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:rawID] : nil;
    if (!uuid) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidIdentifier, @"Theme ID must be a valid UUID.");
        return nil;
    }
    NSString *rawName = dictionary[@"name"];
    NSString *name = [rawName isKindOfClass:NSString.class] ? [rawName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (name.length == 0) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidName, @"Theme name cannot be empty.");
        return nil;
    }
    NSDate *created = ParseDate(dictionary[@"created_at"]);
    NSDate *updated = ParseDate(dictionary[@"updated_at"]);
    if (!created || !updated) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidDocument, @"Theme dates must be valid ISO-8601 strings.");
        return nil;
    }
    NSDictionary *light = NormalizeColors(dictionary[@"light"], YES, error);
    if (!light) return nil;
    NSDictionary *dark = NormalizeColors(dictionary[@"dark"], YES, error);
    if (!dark) return nil;

    id advancedValue = dictionary[@"advanced"];
    if (!advancedValue && legacy) advancedValue = @{@"light":@{}, @"dark":@{}};
    if (![advancedValue isKindOfClass:NSDictionary.class] ||
        ![[NSSet setWithArray:[advancedValue allKeys]] isEqualToSet:[NSSet setWithArray:@[@"light", @"dark"]]]) {
        if (error) *error = ThemeError(DirectColorThemeErrorInvalidAdvancedOverrides, @"Advanced overrides must contain exactly light and dark dictionaries.");
        return nil;
    }
    NSDictionary *advancedLight = NormalizeColors(advancedValue[@"light"], NO, error);
    if (!advancedLight) return nil;
    NSDictionary *advancedDark = NormalizeColors(advancedValue[@"dark"], NO, error);
    if (!advancedDark) return nil;

    DirectColorTheme *theme = [[self alloc] init];
    theme.identifier = uuid.UUIDString.uppercaseString;
    theme.name = name;
    theme.createdAt = created;
    theme.updatedAt = updated;
    theme.lightColors = light;
    theme.darkColors = dark;
    theme.advancedOverrides = @{@"light":advancedLight, @"dark":advancedDark};
    return theme;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{@"schema_version":@1, @"id":self.identifier, @"name":self.name, @"source":@"custom",
        @"created_at":FormatDate(self.createdAt), @"updated_at":FormatDate(self.updatedAt),
        @"light":self.lightColors, @"dark":self.darkColors, @"advanced":self.advancedOverrides};
}

- (NSDictionary *)applicationSnapshot {
    return @{@"schema_version":@2, @"preset":NSNull.null, @"custom_theme_id":self.identifier,
        @"light":self.lightColors, @"dark":self.darkColors, @"advanced":self.advancedOverrides};
}

@end
