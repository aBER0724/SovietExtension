#import <Foundation/Foundation.h>

@class DirectColorTheme;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DirectColorThemeAppearance) {
    DirectColorThemeAppearanceLight = 0,
    DirectColorThemeAppearanceDark = 1,
};

typedef NS_ENUM(NSInteger, DirectColorThemeUnsavedAction) {
    DirectColorThemeUnsavedActionNone = 0,
    DirectColorThemeUnsavedActionSave,
    DirectColorThemeUnsavedActionSaveAs,
};

typedef NS_ENUM(NSInteger, DirectColorThemeUnsavedDecision) {
    DirectColorThemeUnsavedDecisionSave = 0,
    DirectColorThemeUnsavedDecisionDiscard,
    DirectColorThemeUnsavedDecisionCancel,
};

typedef NS_ENUM(NSInteger, DirectColorThemeOperation) {
    DirectColorThemeOperationSelection = 0,
    DirectColorThemeOperationClose,
    DirectColorThemeOperationNew,
    DirectColorThemeOperationDuplicate,
    DirectColorThemeOperationRename,
    DirectColorThemeOperationDelete,
    DirectColorThemeOperationReload,
};

@interface DirectColorThemeEditorState : NSObject

@property (nonatomic, copy, readonly) NSDictionary *builtInPresets;
@property (nonatomic, copy, readonly) NSArray<DirectColorTheme *> *customThemes;
@property (nonatomic, copy, readonly, nullable) NSString *selectedIdentifier;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSString *> *lightColors;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSString *> *darkColors;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *advancedOverrides;
@property (nonatomic) DirectColorThemeAppearance appearance;
@property (nonatomic, readonly, getter=isBuiltIn) BOOL builtIn;
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;
@property (nonatomic, readonly) DirectColorThemeUnsavedAction unsavedAction;
@property (nonatomic, readonly) BOOL requiresSaveAsForApply;
@property (nonatomic, copy, readonly, nullable) NSString *warning;

+ (NSDictionary *)builtInPresets;
+ (nullable NSDictionary *)activeConfigurationFromJSONData:(NSData *)data error:(NSError **)error;
+ (BOOL)operation:(DirectColorThemeOperation)operation
mayProceedWithAction:(DirectColorThemeUnsavedAction)action
         decision:(DirectColorThemeUnsavedDecision)decision
    saveSucceeded:(BOOL)saveSucceeded;
- (instancetype)initWithBuiltInPresets:(NSDictionary *)builtInPresets customThemes:(NSArray<DirectColorTheme *> *)customThemes;
+ (instancetype)stateForActiveConfiguration:(nullable NSDictionary *)configuration
                             builtInPresets:(NSDictionary *)builtInPresets
                                customThemes:(NSArray<DirectColorTheme *> *)customThemes;
- (BOOL)selectIdentifier:(NSString *)identifier;
- (BOOL)changeSelectionTo:(NSString *)identifier
                 decision:(DirectColorThemeUnsavedDecision)decision
              saveHandler:(nullable BOOL (^)(void))saveHandler;
- (BOOL)setColor:(NSString *)color forKey:(NSString *)key appearance:(DirectColorThemeAppearance)appearance;
- (BOOL)updateAdvancedOverrides:(NSDictionary *)advancedOverrides;
- (void)markClean;
- (nullable DirectColorTheme *)selectedCustomTheme;

@end

typedef BOOL (^DirectColorThemeOperationSaveHandler)(void);
typedef void (^DirectColorThemeOperationActionHandler)(void);

@interface DirectColorThemeOperationResult : NSObject
@property (nonatomic, readonly) BOOL proceeded;
@property (nonatomic, readonly) NSUInteger saveAsCount;
@property (nonatomic, readonly) NSUInteger saveCount;
@property (nonatomic, readonly) NSUInteger currentActionCount;
@property (nonatomic, readonly) NSUInteger targetActionCount;
@end

@interface DirectColorThemeOperationCoordinator : NSObject
+ (DirectColorThemeOperationResult *)performOperation:(DirectColorThemeOperation)operation
                                        unsavedAction:(DirectColorThemeUnsavedAction)unsavedAction
                                             decision:(DirectColorThemeUnsavedDecision)decision
                                          saveHandler:(nullable DirectColorThemeOperationSaveHandler)saveHandler
                                        saveAsHandler:(nullable DirectColorThemeOperationSaveHandler)saveAsHandler
                                       currentHandler:(nullable DirectColorThemeOperationActionHandler)currentHandler
                                        targetHandler:(nullable DirectColorThemeOperationActionHandler)targetHandler;
@end

@interface DirectColorThemeApplyResult : NSObject
@property (nonatomic, strong, readonly) DirectColorTheme *authoritativeTheme;
@property (nonatomic, copy, readonly) NSDictionary *applicationSnapshot;
@end

typedef BOOL (^DirectColorThemeSaveHandler)(DirectColorTheme *theme, NSError **error);
typedef NSArray<DirectColorTheme *> * _Nullable (^DirectColorThemeReloadHandler)(NSError **error);

@interface DirectColorThemeApplyCoordinator : NSObject
+ (nullable DirectColorThemeApplyResult *)prepareCustomApplicationForState:(DirectColorThemeEditorState *)state
                                                               sourceTheme:(DirectColorTheme *)sourceTheme
                                                               saveHandler:(DirectColorThemeSaveHandler)saveHandler
                                                             reloadHandler:(DirectColorThemeReloadHandler)reloadHandler
                                                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
