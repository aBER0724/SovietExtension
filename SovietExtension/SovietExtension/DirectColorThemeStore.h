#import <Foundation/Foundation.h>
#import "DirectColorTheme.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const DirectColorThemeStoreErrorDomain;

typedef NS_ERROR_ENUM(DirectColorThemeStoreErrorDomain, DirectColorThemeStoreErrorCode) {
    DirectColorThemeStoreErrorIO = 1,
    DirectColorThemeStoreErrorDuplicateName,
    DirectColorThemeStoreErrorNotFound,
    DirectColorThemeStoreErrorInvalidName,
};

@interface DirectColorThemeStore : NSObject

@property (nonatomic, copy, readonly) NSURL *directoryURL;
@property (nonatomic, copy, readonly) NSArray<DirectColorTheme *> *themes;
@property (nonatomic, copy, readonly) NSArray<NSError *> *errors;

- (instancetype)init;
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL NS_DESIGNATED_INITIALIZER;
- (NSArray<DirectColorTheme *> *)loadThemes:(NSError **)error;
- (nullable DirectColorTheme *)themeWithIdentifier:(NSString *)identifier;
- (nullable DirectColorTheme *)createThemeNamed:(NSString *)name
                                    lightColors:(NSDictionary *)lightColors
                                     darkColors:(NSDictionary *)darkColors
                                          error:(NSError **)error;
- (nullable DirectColorTheme *)duplicateTheme:(DirectColorTheme *)theme
                                         name:(NSString *)name
                                        error:(NSError **)error;
- (nullable DirectColorTheme *)renameTheme:(DirectColorTheme *)theme
                                      name:(NSString *)name
                                     error:(NSError **)error;
- (BOOL)saveTheme:(DirectColorTheme *)theme error:(NSError **)error;
- (BOOL)deleteTheme:(DirectColorTheme *)theme error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
