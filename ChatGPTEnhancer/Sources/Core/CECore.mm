#import "CECore.h"
#import <objc/runtime.h>

NSString * const CEBundleIdentifier = @"com.openai.chat";
NSString * const CEVersion = @"0.1.0-alpha27-diagnostic";
NSString * const CEConversationContextDidChangeNotification = @"ChatGPTEnhancer.ConversationContextDidChange";
NSString * const CENetworkTemplateDidChangeNotification = @"ChatGPTEnhancer.NetworkTemplateDidChange";
NSString * const CECatalogDidChangeNotification = @"ChatGPTEnhancer.CatalogDidChange";

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
    BOOL changed = ![_conversationID isEqualToString:conversationID] || (title.length && ![_title isEqualToString:title]);
    _conversationID = [conversationID copy];
    if (title.length) _title = [title copy];
    _updatedAt = [NSDate date];
    if (changed) [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}

- (void)updateTitle:(NSString *)title {
    if (!title.length || [_title isEqualToString:title]) return;
    _title = [title copy];
    _updatedAt = [NSDate date];
    [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}

- (void)clear {
    if (!_conversationID.length) return;
    _conversationID = nil; _title = nil; _updatedAt = [NSDate date];
    [[NSNotificationCenter defaultCenter] postNotificationName:CEConversationContextDidChangeNotification object:self];
}
@end

BOOL CETargetApp(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:CEBundleIdentifier]; }

UIWindow *CEKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) if (window.isKeyWindow) return window;
        for (UIWindow *window in windowScene.windows) if (!window.hidden && window.alpha > 0.01) return window;
    }
    return UIApplication.sharedApplication.windows.firstObject;
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
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + 28.0, size.height + 18.0);
}
- (void)drawTextInRect:(CGRect)rect { [super drawTextInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(9, 14, 9, 14))]; }
@end

@interface CEMessagePresenter : NSObject
@property (nonatomic, strong) CEMessageLabel *label;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *messageConstraints;
+ (instancetype)shared;
- (void)showMessage:(NSString *)message;
@end

@implementation CEMessagePresenter
+ (instancetype)shared { static CEMessagePresenter *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEMessagePresenter new]; }); return v; }
- (CEMessageLabel *)label {
    if (_label) return _label;
    _label = [CEMessageLabel new];
    _label.textColor = UIColor.whiteColor; _label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.84];
    _label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; _label.textAlignment = NSTextAlignmentCenter; _label.numberOfLines = 3;
    _label.layer.cornerRadius = 12; _label.layer.masksToBounds = YES; _label.translatesAutoresizingMaskIntoConstraints = NO;
    return _label;
}
- (void)showMessage:(NSString *)message {
    if (!message.length) return;
    UIWindow *window = CEKeyWindow(); if (!window) return;
    NSUInteger generation = ++self.generation;
    CEMessageLabel *label = self.label; label.text = message;
    if (label.superview != window) { [label removeFromSuperview]; [window addSubview:label]; self.window = window; }
    if (self.messageConstraints.count) [NSLayoutConstraint deactivateConstraints:self.messageConstraints];
    CGFloat upward = -MIN(MAX(CGRectGetHeight(window.bounds) * 0.08, 40.0), 75.0);
    self.messageConstraints = @[
        [label.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:window.centerYAnchor constant:upward],
        [label.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor multiplier:0.84],
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:40]
    ];
    [NSLayoutConstraint activateConstraints:self.messageConstraints];
    [window bringSubviewToFront:label];
    [label.layer removeAllAnimations]; label.alpha = 1.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.generation) return;
        [UIView animateWithDuration:0.22 animations:^{ label.alpha = 0; } completion:^(__unused BOOL finished) {
            if (generation == self.generation) [label removeFromSuperview];
        }];
    });
}
@end

void CEShowMessage(NSString *message) {
    if (!message.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [[CEMessagePresenter shared] showMessage:message]; });
}

void CEShowAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = CETopViewController(); if (!vc) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
    });
}

NSString *CESanitizeFilename(NSString *name) {
    NSString *value = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length) value = @"ChatGPT Conversation";
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>\n\r\t"];
    value = [[value componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    while ([value containsString:@"__"]) value = [value stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    if (value.length > 120) value = [value substringToIndex:120];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ._"]];
}

NSString *CEExtractConversationIDFromString(NSString *value) {
    if (!value.length) return nil;
    static NSRegularExpression *uuidRE; static NSRegularExpression *pathRE; static dispatch_once_t once;
    dispatch_once(&once, ^{
        uuidRE = [NSRegularExpression regularExpressionWithPattern:@"(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})" options:0 error:nil];
        pathRE = [NSRegularExpression regularExpressionWithPattern:@"(?i)/(?:c|conversation)/([^/?#]{16,})" options:0 error:nil];
    });
    NSRange all = NSMakeRange(0, value.length); NSTextCheckingResult *m = [uuidRE firstMatchInString:value options:0 range:all];
    if (m.numberOfRanges > 1) return [value substringWithRange:[m rangeAtIndex:1]];
    m = [pathRE firstMatchInString:value options:0 range:all];
    if (m.numberOfRanges > 1) return [value substringWithRange:[m rangeAtIndex:1]];
    return nil;
}

static void CECollectStringsRecursive(UIView *view, NSUInteger depth, NSUInteger maxDepth, NSMutableOrderedSet<NSString *> *out) {
    if (!view || depth > maxDepth) return;
    NSArray *values = @[
        view.accessibilityIdentifier ?: @"", view.accessibilityLabel ?: @"", view.accessibilityValue ?: @"",
        [view isKindOfClass:UILabel.class] ? (((UILabel *)view).text ?: @"") : @"",
        [view isKindOfClass:UIButton.class] ? ([((UIButton *)view) titleForState:UIControlStateNormal] ?: @"") : @""
    ];
    for (NSString *value in values) {
        NSString *trim = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trim.length && trim.length < 240) [out addObject:trim];
    }
    for (UIView *child in view.subviews) CECollectStringsRecursive(child, depth + 1, maxDepth, out);
}

NSArray<NSString *> *CECollectVisibleStrings(UIView *view, NSUInteger maxDepth) {
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    UIView *cursor = view;
    for (NSUInteger up = 0; cursor && up < 5; up++, cursor = cursor.superview) CECollectStringsRecursive(cursor, 0, MIN(maxDepth, 5), set);
    return set.array;
}

BOOL CESwizzleInstanceMethod(Class cls, SEL originalSelector, SEL swizzledSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector), swizzled = class_getInstanceMethod(cls, swizzledSelector);
    if (!original || !swizzled) return NO;
    BOOL added = class_addMethod(cls, originalSelector, method_getImplementation(swizzled), method_getTypeEncoding(swizzled));
    if (added) class_replaceMethod(cls, swizzledSelector, method_getImplementation(original), method_getTypeEncoding(original));
    else method_exchangeImplementations(original, swizzled);
    return YES;
}

BOOL CESwizzleClassMethod(Class cls, SEL originalSelector, SEL swizzledSelector) {
    return CESwizzleInstanceMethod(object_getClass(cls), originalSelector, swizzledSelector);
}
