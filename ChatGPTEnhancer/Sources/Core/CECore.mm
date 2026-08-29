#import "CECore.h"
#import <objc/runtime.h>

NSString * const CEBundleIdentifier = @"com.openai.chat";
NSString * const CEVersion = @"0.1.0-alpha58-reentry-network-trace";
NSString * const CEConversationContextDidChangeNotification = @"ChatGPTEnhancer.ConversationContextDidChange";
NSString * const CENetworkTemplateDidChangeNotification = @"ChatGPTEnhancer.NetworkTemplateDidChange";
NSString * const CECatalogDidChangeNotification = @"ChatGPTEnhancer.CatalogDidChange";
NSInteger const CESyntheticConversationTitleMarkerTag = 0x43454844;

@implementation CEConversationContext {
    NSString *_conversationID;
    NSString *_title;
    NSDate *_updatedAt;
}

+ (instancetype)shared { static CEConversationContext *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEConversationContext new]; }); return v; }
- (NSString *)conversationID { return _conversationID; }
- (NSString *)title { return _title; }
- (NSDate *)updatedAt { return _updatedAt; }

- (void)setConversationID:(NSString *)conversationID title:(NSString *)title {
    if (!conversationID.length) return;
    BOOL idChanged = ![_conversationID isEqualToString:conversationID];
    BOOL titleChanged = title.length && ![_title isEqualToString:title];
    BOOL changed = idChanged || titleChanged;
    _conversationID = [conversationID copy];
    if (idChanged) _title = title.length ? [title copy] : nil;
    else if (title.length) _title = [title copy];
    _updatedAt = [NSDate date];
    if (changed) [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}

- (void)updateTitle:(NSString *)title {
    if (!title.length || [_title isEqualToString:title]) return;
    _title = [title copy]; _updatedAt = [NSDate date];
    [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}

- (void)clear {
    if (!_conversationID.length) return;
    _conversationID = nil; _title = nil; _updatedAt = [NSDate date];
    [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}
@end

BOOL CETargetApp(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:CEBundleIdentifier]; }

NSArray<UIWindow *> *CEForegroundWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (!window.hidden && window.alpha > 0.01) [windows addObject:window];
    }
    if (!windows.count) for (UIWindow *window in UIApplication.sharedApplication.windows) if (!window.hidden && window.alpha > 0.01) [windows addObject:window];
    return windows;
}

UIWindow *CEKeyWindow(void) {
    for (UIWindow *window in CEForegroundWindows()) if (window.isKeyWindow) return window;
    return CEForegroundWindows().firstObject ?: UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *CETopFrom(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return CETopFrom(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return CETopFrom(((UINavigationController *)vc).visibleViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return CETopFrom(((UITabBarController *)vc).selectedViewController);
    for (UIViewController *child in vc.childViewControllers.reverseObjectEnumerator) if (child.viewIfLoaded.window) return CETopFrom(child);
    return vc;
}
UIViewController *CETopViewController(void) { return CETopFrom(CEKeyWindow().rootViewController); }

@interface CEMessageLabel : UILabel
@end
@implementation CEMessageLabel
- (CGSize)intrinsicContentSize { CGSize size = [super intrinsicContentSize]; return CGSizeMake(size.width + 28.0, size.height + 18.0); }
- (void)drawTextInRect:(CGRect)rect { [super drawTextInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(9, 14, 9, 14))]; }
@end

void CEShowMessage(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = CEKeyWindow(); if (!window) return;
        for (UIView *view in [window.subviews copy]) if ([view isKindOfClass:CEMessageLabel.class]) [view removeFromSuperview];
        CEMessageLabel *label = [CEMessageLabel new]; label.text = message ?: @""; label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.94]; label.layer.cornerRadius = 12; label.layer.masksToBounds = YES; label.textAlignment = NSTextAlignmentCenter; label.numberOfLines = 0; label.translatesAutoresizingMaskIntoConstraints = NO; [window addSubview:label];
        [NSLayoutConstraint activateConstraints:@[[label.centerXAnchor constraintEqualToAnchor:window.centerXAnchor], [label.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-86], [label.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor multiplier:0.88]]];
        [UIView animateWithDuration:0.18 animations:^{ label.alpha = 1.0; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [UIView animateWithDuration:0.18 animations:^{ label.alpha = 0.0; } completion:^(__unused BOOL finished) { [label removeFromSuperview]; }]; });
    });
}

NSString *CESanitizeFilename(NSString *name) {
    NSString *value = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!value.length) value = @"ChatGPT Conversation";
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>\n\r\t"];
    value = [[value componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    while ([value containsString:@"__"]) value = [value stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    if (value.length > 120) value = [value substringToIndex:120];
    return value.length ? value : @"ChatGPT Conversation";
}

NSString *CEExtractConversationIDFromString(NSString *text) {
    if (!text.length) return nil;
    static NSRegularExpression *re; static dispatch_once_t once;
    dispatch_once(&once, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})" options:0 error:nil]; });
    NSTextCheckingResult *match = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]; return match.numberOfRanges > 1 ? [text substringWithRange:[match rangeAtIndex:1]] : nil;
}

void CESwizzleInstanceMethod(Class cls, SEL original, SEL replacement) { Method a = class_getInstanceMethod(cls, original), b = class_getInstanceMethod(cls, replacement); if (a && b) method_exchangeImplementations(a, b); }
void CESwizzleClassMethod(Class cls, SEL original, SEL replacement) { Method a = class_getClassMethod(cls, original), b = class_getClassMethod(cls, replacement); if (a && b) method_exchangeImplementations(a, b); }

NSArray<NSString *> *CECollectVisibleStrings(UIView *view, NSUInteger depth) {
    if (!view || depth > 18) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) [out addObject:((UILabel *)view).text];
    if ([view isKindOfClass:UITextView.class] && ((UITextView *)view).text.length) [out addObject:((UITextView *)view).text];
    if ([view isKindOfClass:UITextField.class] && ((UITextField *)view).text.length) [out addObject:((UITextField *)view).text];
    if ([view isKindOfClass:UIButton.class] && [((UIButton *)view) titleForState:UIControlStateNormal].length) [out addObject:[((UIButton *)view) titleForState:UIControlStateNormal]];
    for (UIView *child in view.subviews) [out addObjectsFromArray:CECollectVisibleStrings(child, depth + 1)];
    return out;
}