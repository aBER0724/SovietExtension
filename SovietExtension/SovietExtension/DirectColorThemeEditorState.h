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
@property (nonatomic, copy, readonly, nullable) NSString *warning;

+ (NSDictionary *)builtInPresets;
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
- (NSDictionary *)applicationSnapshotForCustomIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
