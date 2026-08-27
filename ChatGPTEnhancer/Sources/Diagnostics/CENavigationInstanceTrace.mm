#import "CENavigationInstanceTrace.h"
#import "CEConversationIdentityTrace.h"
#import "../Core/CECore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const void *CENavigationInstanceTokenKey = &CENavigationInstanceTokenKey;
static NSUInteger CENavigationInstanceTokenSequence = 0;

static NSString *CENavigationInstanceToken(UINavigationController *nav) {
    if (!nav) return @"<none>";
    NSString *token = objc_getAssociatedObject(nav, CENavigationInstanceTokenKey); if (token.length) return token;
    @synchronized (UINavigationController.class) {
        token = objc_getAssociatedObject(nav, CENavigationInstanceTokenKey);
        if (!token.length) { token = [NSString stringWithFormat:@"nav-%lu", (unsigned long)++CENavigationInstanceTokenSequence]; objc_setAssociatedObject(nav, CENavigationInstanceTokenKey, token, OBJC_ASSOCIATION_COPY_NONATOMIC); }
    }
    return token;
}

static NSString *CENavigationInstanceStack(UINavigationController *nav) {
    NSMutableArray<NSString *> *classes = [NSMutableArray array];
    for (UIViewController *controller in nav.viewControllers ?: @[]) { [classes addObject:NSStringFromClass(controller.class) ?: @"<unknown>"]; if (classes.count >= 8) break; }
    return classes.count ? [classes componentsJoinedByString:@">"] : @"<empty>";
}

static void CECollectNavigationInstances(UIViewController *controller, NSMutableOrderedSet<UINavigationController *> *out, NSUInteger depth) {
    if (!controller || depth > 16) return;
    if ([controller isKindOfClass:UINavigationController.class]) [out addObject:(UINavigationController *)controller];
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) CECollectNavigationInstances(controller.presentedViewController, out, depth + 1);
    for (UIViewController *child in controller.childViewControllers ?: @[]) CECollectNavigationInstances(child, out, depth + 1);
}

void CENavigationInstanceTraceSnapshot(NSString *reason) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ CENavigationInstanceTraceSnapshot(reason); }); return; }
    NSMutableOrderedSet<UINavigationController *> *navs = [NSMutableOrderedSet orderedSet];
    for (UIWindow *window in CEForegroundWindows()) CECollectNavigationInstances(window.rootViewController, navs, 0);
    UIViewController *top = CETopViewController(); UINavigationController *activeNav = [top isKindOfClass:UINavigationController.class] ? (UINavigationController *)top : top.navigationController;
    if (activeNav) [navs addObject:activeNav];
    if (!navs.count) { CEConversationIdentityTraceLog(@"NAV-INSTANCE", @"reason=%@ count=0", reason ?: @"<none>"); return; }
    NSUInteger index = 0;
    for (UINavigationController *nav in navs) {
        UIWindow *window = nav.viewIfLoaded.window;
        CEConversationIdentityTraceLog(@"NAV-INSTANCE", @"reason=%@ index=%lu token=%@ nav=%@ count=%lu stack=%@ visible=%@ attached=%@ window=%@ windowKey=%@ active=%@ parent=%@ presenting=%@ presented=%@",
            reason ?: @"<none>", (unsigned long)index++, CENavigationInstanceToken(nav), NSStringFromClass(nav.class) ?: @"<none>", (unsigned long)nav.viewControllers.count, CENavigationInstanceStack(nav),
            nav.visibleViewController ? NSStringFromClass(nav.visibleViewController.class) : @"<none>", window ? @"YES" : @"NO", window ? NSStringFromClass(window.class) : @"<none>", window.isKeyWindow ? @"YES" : @"NO", nav == activeNav ? @"YES" : @"NO",
            nav.parentViewController ? NSStringFromClass(nav.parentViewController.class) : @"<none>", nav.presentingViewController ? NSStringFromClass(nav.presentingViewController.class) : @"<none>", nav.presentedViewController ? NSStringFromClass(nav.presentedViewController.class) : @"<none>");
    }
}
