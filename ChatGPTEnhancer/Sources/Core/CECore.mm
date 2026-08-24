#import "CECore.h"
#import <objc/runtime.h>

NSString * const CEBundleIdentifier = @"com.openai.chat";
NSString * const CEVersion = @"0.1.0-alpha33-lifecycle-stability";
NSString * const CEConversationContextDidChangeNotification = @"ChatGPTEnhancer.ConversationContextDidChange";
NSString * const CENetworkTemplateDidChangeNotification = @"ChatGPTEnhancer.NetworkTemplateDidChange";
NSString * const CECatalogDidChangeNotification = @"ChatGPTEnhancer.CatalogDidChange";

@implementation CEConversationContext {
    NSString *_conversationID;
    NSString *_title;
    NSDate *_updatedAt;
}

+ (instancetype)shared {
    static CEConversationContext *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [CEConversationContext new]; });
    return value;
}

- (NSString *)conversationID { @synchronized (self) { return _conversationID; } }
- (NSString *)title { @synchronized (self) { return _title; } }
- (NSDate *)updatedAt { @synchronized (self) { return _updatedAt; } }

- (void)setConversationID:(NSString *)conversationID title:(NSString *)title {
    if (!conversationID.length) return;
    BOOL changed = NO;
    @synchronized (self) {
        changed = ![_conversationID isEqualToString:conversationID] || (title.length && ![_title isEqualToString:title]);
        _conversationID = [conversationID copy]; if (title.length) _title = [title copy]; _updatedAt = [NSDate date];
    }
    if (changed) [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}

- (void)clear {
    BOOL changed = NO;
    @synchronized (self) { changed = _conversationID.length > 0 || _title.length > 0; _conversationID = nil; _title = nil; _updatedAt = nil; }
    if (changed) [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}
@end

BOOL CETargetApp(void) { return [NSBundle.mainBundle.bundleIdentifier isEqualToString:CEBundleIdentifier]; }

UIWindow *CEKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *window in ((UIWindowScene *)scene).windows) if (!window.hidden) return window;
    return nil;
}

UIViewController *CETopViewController(void) {
    UIViewController *vc = CEKeyWindow().rootViewController;
    while (vc) {
        if (vc.presentedViewController) { vc = vc.presentedViewController; continue; }
        if ([vc isKindOfClass:UINavigationController.class]) { vc = ((UINavigationController *)vc).visibleViewController; continue; }
        if ([vc isKindOfClass:UITabBarController.class]) { vc = ((UITabBarController *)vc).selectedViewController; continue; }
        break;
    }
    return vc;
}

NSString *CEExtractConversationIDFromString(NSString *text) {
    if (!text.length) return nil;
    static NSRegularExpression *regex; static dispatch_once_t once;
    dispatch_once(&once, ^{ regex = [NSRegularExpression regularExpressionWithPattern:@"(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})" options:0 error:nil]; });
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match.numberOfRanges > 1 ? [text substringWithRange:[match rangeAtIndex:1]].lowercaseString : nil;
}

void CEShowMessage(NSString *message) {
    if (!message.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = CEKeyWindow(); if (!window) return;
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero]; label.text = message; label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85]; label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; label.textAlignment = NSTextAlignmentCenter; label.numberOfLines = 0; label.layer.cornerRadius = 12; label.clipsToBounds = YES;
        CGSize max = CGSizeMake(MIN(window.bounds.size.width - 48, 340), CGFLOAT_MAX); CGSize text = [label sizeThatFits:max]; CGFloat width = MIN(MAX(text.width + 28, 120), max.width); CGFloat height = MAX(text.height + 20, 44); label.frame = CGRectMake((window.bounds.size.width - width) / 2.0, window.safeAreaInsets.top + 72, width, height); label.alpha = 0; [window addSubview:label];
        [UIView animateWithDuration:0.18 animations:^{ label.alpha = 1; } completion:^(__unused BOOL finished) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [UIView animateWithDuration:0.2 animations:^{ label.alpha = 0; } completion:^(__unused BOOL done) { [label removeFromSuperview]; }]; }); }];
    });
}

void CESwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    if (!cls) return;
    Method a = class_getInstanceMethod(cls, original), b = class_getInstanceMethod(cls, replacement); if (!a || !b) return;
    if (class_addMethod(cls, original, method_getImplementation(b), method_getTypeEncoding(b))) class_replaceMethod(cls, replacement, method_getImplementation(a), method_getTypeEncoding(a)); else method_exchangeImplementations(a, b);
}

NSArray<NSString *> *CECollectVisibleStrings(UIView *root, NSUInteger maxDepth) {
    if (!root) return @[];
    NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet];
    __block void (^walk)(UIView *, NSUInteger);
    walk = ^(UIView *view, NSUInteger depth) {
        if (!view || depth > maxDepth || view.hidden || view.alpha < 0.01) return;
        if ([view isKindOfClass:UILabel.class]) { NSString *text = ((UILabel *)view).text; if (text.length) [out addObject:text]; }
        else if ([view isKindOfClass:UIButton.class]) { NSString *text = [((UIButton *)view) titleForState:UIControlStateNormal]; if (text.length) [out addObject:text]; }
        else if ([view isKindOfClass:UITextView.class]) { NSString *text = ((UITextView *)view).text; if (text.length) [out addObject:text]; }
        NSString *label = view.accessibilityLabel; if (label.length) [out addObject:label];
        for (UIView *child in view.subviews) walk(child, depth + 1);
    };
    walk(root, 0); return out.array;
}
