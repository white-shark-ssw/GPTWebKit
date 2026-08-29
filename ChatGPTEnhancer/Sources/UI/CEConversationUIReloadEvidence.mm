#import "CEEnhancerUI.h"
#import "../Core/CECore.h"
#import <UIKit/UIKit.h>

@interface CEConversationUIReloadSnapshot : NSObject
@property (nonatomic) uintptr_t navigationIdentity;
@property (nonatomic) uintptr_t scrollIdentity;
@property (nonatomic, strong) NSSet<NSNumber *> *anchorIdentities;
@end
@implementation CEConversationUIReloadSnapshot @end

static UINavigationController *CEActiveAttachedNavigationController(void) {
    UIViewController *top = CETopViewController(); UINavigationController *nav = [top isKindOfClass:UINavigationController.class] ? (UINavigationController *)top : top.navigationController;
    UIWindow *window = nav.viewIfLoaded.window; if (!nav || !window || window.hidden || window.alpha < 0.02) return nil; return nav;
}

static void CEFindConversationScrollView(UIView *view, UIWindow *window, NSUInteger depth, UIScrollView **best, UIWindow **bestWindow, CGFloat *bestScore) {
    if (!view || depth > 18 || view.hidden || view.alpha < 0.02 || !view.window) return;
    if ([view isKindOfClass:UIScrollView.class] && ![view isKindOfClass:UITextView.class]) {
        CGRect frame = [view convertRect:view.bounds toView:window];
        CGFloat widthRatio = CGRectGetWidth(frame) / MAX(CGRectGetWidth(window.bounds), 1.0); CGFloat heightRatio = CGRectGetHeight(frame) / MAX(CGRectGetHeight(window.bounds), 1.0);
        CGFloat contentTop = window.safeAreaInsets.top + 72.0; CGFloat contentBottom = CGRectGetHeight(window.bounds) - window.safeAreaInsets.bottom - 72.0;
        CGRect contentBand = CGRectMake(0, contentTop, CGRectGetWidth(window.bounds), MAX(1.0, contentBottom - contentTop));
        if (widthRatio >= 0.55 && heightRatio >= 0.28 && CGRectIntersectsRect(frame, contentBand)) {
            UIScrollView *scroll = (UIScrollView *)view; CGFloat score = CGRectGetWidth(frame) * CGRectGetHeight(frame) + MIN(MAX(scroll.contentSize.height, 0.0), CGRectGetHeight(window.bounds) * 6.0) * 20.0;
            if (score > *bestScore) { *best = scroll; *bestWindow = window; *bestScore = score; }
        }
    }
    for (UIView *child in view.subviews) CEFindConversationScrollView(child, window, depth + 1, best, bestWindow, bestScore);
}

static BOOL CEViewIsReloadAnchor(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return [((UILabel *)view).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    if ([view isKindOfClass:UITextView.class]) return [((UITextView *)view).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    NSString *label = [view.accessibilityLabel isKindOfClass:NSString.class] ? [view.accessibilityLabel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    return view.isAccessibilityElement && label.length > 0;
}

static void CECollectReloadAnchors(UIView *view, UIScrollView *scroll, UIWindow *window, NSUInteger depth, NSMutableSet<NSNumber *> *anchors) {
    if (!view || depth > 20 || anchors.count >= 512 || view.hidden || view.alpha < 0.02 || !view.window) return;
    CGRect frame = [view convertRect:view.bounds toView:window]; CGFloat contentTop = window.safeAreaInsets.top + 72.0; CGFloat contentBottom = CGRectGetHeight(window.bounds) - window.safeAreaInsets.bottom - 72.0;
    if (view != scroll && CGRectGetMaxY(frame) >= contentTop && CGRectGetMinY(frame) <= contentBottom && CGRectIntersectsRect(frame, window.bounds) && CEViewIsReloadAnchor(view)) {
        uintptr_t identity = (uintptr_t)(__bridge void *)view; if (identity) [anchors addObject:@((unsigned long long)identity)];
    }
    for (UIView *child in view.subviews) CECollectReloadAnchors(child, scroll, window, depth + 1, anchors);
}

NSObject *CECaptureCurrentConversationUIReloadSnapshot(void) {
    if (!NSThread.isMainThread) return nil;
    CEConversationUIReloadSnapshot *snapshot = [CEConversationUIReloadSnapshot new]; UINavigationController *nav = CEActiveAttachedNavigationController(); snapshot.navigationIdentity = (uintptr_t)(__bridge void *)nav;
    UIScrollView *scroll = nil; UIWindow *surfaceWindow = nil; CGFloat bestScore = -CGFLOAT_MAX;
    for (UIWindow *window in CEForegroundWindows()) CEFindConversationScrollView(window, window, 0, &scroll, &surfaceWindow, &bestScore);
    NSMutableSet<NSNumber *> *anchors = [NSMutableSet set];
    if (scroll && surfaceWindow) { snapshot.scrollIdentity = (uintptr_t)(__bridge void *)scroll; CECollectReloadAnchors(scroll, scroll, surfaceWindow, 0, anchors); }
    snapshot.anchorIdentities = [anchors copy]; return snapshot.navigationIdentity || snapshot.scrollIdentity ? snapshot : nil;
}

BOOL CECurrentConversationUIReloadSnapshotHasContent(NSObject *snapshot) {
    if (![snapshot isKindOfClass:CEConversationUIReloadSnapshot.class]) return NO;
    CEConversationUIReloadSnapshot *value = (CEConversationUIReloadSnapshot *)snapshot; return value.scrollIdentity != 0 && value.anchorIdentities.count > 0;
}

BOOL CECurrentConversationUIReloadSnapshotShowsRebuild(NSObject *baseline, NSObject *current) {
    if (![baseline isKindOfClass:CEConversationUIReloadSnapshot.class] || ![current isKindOfClass:CEConversationUIReloadSnapshot.class]) return NO;
    CEConversationUIReloadSnapshot *before = (CEConversationUIReloadSnapshot *)baseline; CEConversationUIReloadSnapshot *after = (CEConversationUIReloadSnapshot *)current;
    if (before.navigationIdentity && after.navigationIdentity && before.navigationIdentity != after.navigationIdentity) return YES;
    if (before.scrollIdentity && after.scrollIdentity && before.scrollIdentity != after.scrollIdentity) return YES;
    NSUInteger beforeCount = before.anchorIdentities.count, afterCount = after.anchorIdentities.count, minimum = MIN(beforeCount, afterCount); if (!minimum) return NO;
    NSMutableSet<NSNumber *> *shared = [before.anchorIdentities mutableCopy]; [shared intersectSet:after.anchorIdentities];
    if (minimum == 1) return shared.count == 0;
    return shared.count * 2 < minimum && beforeCount > shared.count && afterCount > shared.count;
}