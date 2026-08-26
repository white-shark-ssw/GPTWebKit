#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const CEBundleIdentifier;
FOUNDATION_EXPORT NSString * const CEVersion;
FOUNDATION_EXPORT NSString * const CEConversationContextDidChangeNotification;
FOUNDATION_EXPORT NSString * const CENetworkTemplateDidChangeNotification;
FOUNDATION_EXPORT NSString * const CECatalogDidChangeNotification;
FOUNDATION_EXPORT NSInteger const CESyntheticConversationTitleMarkerTag;

@interface CEConversationContext : NSObject
@property (nonatomic, copy, nullable, readonly) NSString *conversationID;
@property (nonatomic, copy, nullable, readonly) NSString *title;
@property (nonatomic, strong, nullable, readonly) NSDate *updatedAt;
+ (instancetype)shared;
- (void)setConversationID:(NSString *)conversationID title:(nullable NSString *)title;
- (void)updateTitle:(nullable NSString *)title;
- (void)clear;
@end

BOOL CETargetApp(void);
UIWindow * _Nullable CEKeyWindow(void);
UIViewController * _Nullable CETopViewController(void);
void CEShowMessage(NSString *message);
void CEShowAlert(NSString *title, NSString *message);
NSString *CESanitizeFilename(NSString *name);
NSString * _Nullable CEExtractConversationIDFromString(NSString *value);
NSArray<NSString *> *CECollectVisibleStrings(UIView *view, NSUInteger maxDepth);
NSString * _Nullable CERefreshVisibleConversationContext(void);
BOOL CESwizzleInstanceMethod(Class cls, SEL originalSelector, SEL swizzledSelector);
BOOL CESwizzleClassMethod(Class cls, SEL originalSelector, SEL swizzledSelector);

NS_ASSUME_NONNULL_END
