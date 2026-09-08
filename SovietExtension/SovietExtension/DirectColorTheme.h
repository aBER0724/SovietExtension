#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const DirectColorThemeErrorDomain;

typedef NS_ERROR_ENUM(DirectColorThemeErrorDomain, DirectColorThemeErrorCode) {
    DirectColorThemeErrorInvalidDocument = 1,
    DirectColorThemeErrorInvalidIdentifier,
    DirectColorThemeErrorInvalidName,
    DirectColorThemeErrorInvalidColors,
    DirectColorThemeErrorInvalidAdvancedOverrides,
};

@interface DirectColorTheme : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSDate *createdAt;
@property (nonatomic, copy, readonly) NSDate *updatedAt;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *lightColors;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *darkColors;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *advancedOverrides;

+ (NSSet<NSString *> *)requiredColorKeys;
+ (nullable instancetype)themeFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;
- (NSDictionary *)dictionaryRepresentation;
- (NSDictionary *)applicationSnapshot;

@end

NS_ASSUME_NONNULL_END
