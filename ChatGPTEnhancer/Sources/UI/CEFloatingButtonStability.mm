#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "../Core/CECore.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"

static BOOL CEFloatHasVisibleMessagesController(UIViewController *vc, NSUInteger depth) {
    if (!vc || depth > 18) return NO;
    if ([NSStringFromClass(vc.class) isEqualToString:@"ChatGPTMessages.MessagesViewController"] && vc.viewIfLoaded.window && !vc.isBeingDismissed && !vc.isMovingFromParentViewController) return YES;
    if (vc.presentedViewController && CEFloatHasVisibleMessagesController(vc.presentedViewController, depth + 1)) return YES;
    for (UIViewController *child in vc.childViewControllers) if (CEFloatHasVisibleMessagesController(child, depth + 1)) return YES;
    return NO;
}

static BOOL CEFloatCurrentConversationStillVisible(void) {
    UIWindow *window = CEKeyWindow();
    return window && CEFloatHasVisibleMessagesController(window.rootViewController, 0);
}

static void CEFloatEnsureAttached(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![CEConversationContext shared].conversationID.length) return;
        Class cls = NSClassFromString(@"CEFloatingButtonController"); SEL sharedSEL = NSSelectorFromString(@"shared"), refreshSEL = NSSelectorFromString(@"contextChanged:");
        if (!cls || ![cls respondsToSelector:sharedSEL]) return;
        id controller = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSEL);
        if (controller && [controller respondsToSelector:refreshSEL]) ((void (*)(id, SEL, id))objc_msgSend)(controller, refreshSEL, nil);
    });
}

@interface CEConversationContext (CEFloatingButtonStability)
- (void)ce_float38_clear;
@end

@implementation CEConversationContext (CEFloatingButtonStability)
- (void)ce_float38_clear {
    if (self.conversationID.length && CEFloatCurrentConversationStillVisible()) {
        CERecoveryDiagnosticLog(@"FLOAT38", @"suppressed context clear while active MessagesViewController remains visible conversation=%@", self.conversationID);
        CEFloatEnsureAttached();
        return;
    }
    [self ce_float38_clear];
}
@end

__attribute__((constructor)) static void CEFloatingButtonStabilityEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        static dispatch_once_t once; dispatch_once(&once, ^{
            CESwizzleInstanceMethod(CEConversationContext.class, @selector(clear), @selector(ce_float38_clear));
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEFloatEnsureAttached(); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEFloatEnsureAttached(); }); }];
            [center addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEFloatEnsureAttached(); }];
            [center addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEFloatEnsureAttached(); }];
            CERecoveryDiagnosticLog(@"FLOAT38", @"floating-button interactive-swipe stability guard installed");
        });
    }
}
