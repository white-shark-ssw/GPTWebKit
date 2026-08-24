#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Network/CENetworkObserver.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "CEOrphanedConversationRecovery.h"

static IMP CEOrphanOriginalHistoryDidSelectIMP = NULL;
static BOOL CEOrphanHistorySelectionHookInstalled = NO;
static NSUInteger CEOrphanHistorySelectionGeneration = 0;
static NSString *CEOrphanConfirmedHistoryConversationID = nil;
static NSIndexPath *CEOrphanConfirmedHistoryIndexPath = nil;
static NSDate *CEOrphanConfirmedHistoryAt = nil;
static UICollectionView *CEOrphanConfirmedHistoryCollection = nil;
static NSString *CEOrphanConfirmedHistorySource = nil;
static BOOL CEOrphanConfirmedHistoryStrong = NO;
static NSString *CEOrphanLastManualReloadState = nil;
static NSString *CEOrphanLastSoftRefreshState = nil;
static NSString *CEOrphanLastNativeReplayState = @"disabled: navigation safety guard";
static NSString *CEOrphanLastTargetSource = @"disabled: no programmatic navigation";
static NSString *CEOrphanLastSidebarCandidate = @"disabled: no sidebar automation";

static NSString *CEOrphanIndexPathsDescription(NSArray<NSIndexPath *> *paths) {
    if (!paths.count) return @"()";
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSIndexPath *path in paths) [values addObject:[NSString stringWithFormat:@"%ld:%ld", (long)path.section, (long)path.item]];
    return [NSString stringWithFormat:@"(%@)", [values componentsJoinedByString:@", "]];
}

static BOOL CEOrphanRecentDetailRequestForConversationSince(NSString *conversationID, NSDate *date) {
    if (!conversationID.length || !date) return NO;
    long long threshold = (long long)(date.timeIntervalSince1970 * 1000.0);
    NSString *cid = conversationID.lowercaseString;
    for (NSString *event in [CENetworkObserver shared].recentEvents.reverseObjectEnumerator) {
        long long timestamp = event.longLongValue; if (timestamp && timestamp < threshold) break;
        NSString *lower = event.lowercaseString;
        if (![lower containsString:@" req "]) continue;
        if ([lower containsString:[NSString stringWithFormat:@"/backend-api/conversation/%@", cid]] || [lower containsString:[NSString stringWithFormat:@"/backend-api/f/conversation/%@", cid]]) return YES;
    }
    return NO;
}

static BOOL CEOrphanRecentResumeRequestSince(NSDate *date) {
    if (!date) return NO;
    long long threshold = (long long)(date.timeIntervalSince1970 * 1000.0);
    for (NSString *event in [CENetworkObserver shared].recentEvents.reverseObjectEnumerator) {
        long long timestamp = event.longLongValue; if (timestamp && timestamp < threshold) break;
        NSString *lower = event.lowercaseString;
        if (![lower containsString:@" req post "]) continue;
        if ([lower containsString:@"/backend-api/f/conversation/resume"]) return YES;
    }
    return NO;
}

static UIViewController *CEOrphanFindHistoryController(UIViewController *vc, NSUInteger depth) {
    if (!vc || depth > 14) return nil;
    if ([NSStringFromClass(vc.class) isEqualToString:@"ChatGPTHistory.HistoryViewController"]) return vc;
    if (vc.presentedViewController) { UIViewController *found = CEOrphanFindHistoryController(vc.presentedViewController, depth + 1); if (found) return found; }
    for (UIViewController *child in vc.childViewControllers) { UIViewController *found = CEOrphanFindHistoryController(child, depth + 1); if (found) return found; }
    return nil;
}

static UICollectionView *CEOrphanFindHistoryCollection(UIView *view, NSUInteger depth) {
    if (!view || depth > 18) return nil;
    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection = (UICollectionView *)view;
        NSString *dataSourceClass = collection.dataSource ? NSStringFromClass([(id)collection.dataSource class]) : @"";
        if ([dataSourceClass containsString:@"ChatGPTHistory"] || [dataSourceClass containsString:@"UICollectionViewDiffableDataSource"]) return collection;
    }
    for (UIView *child in view.subviews) { UICollectionView *found = CEOrphanFindHistoryCollection(child, depth + 1); if (found) return found; }
    return nil;
}

static void CEOrphanConfirmHistorySelection(UICollectionView *collection, NSIndexPath *indexPath, NSString *contextBefore, NSDate *selectedAt, NSUInteger generation) {
    if (generation != CEOrphanHistorySelectionGeneration || !collection || !indexPath || !selectedAt) return;
    NSString *conversationID = [[CEConversationContext shared].conversationID copy];
    if (!conversationID.length) return;
    BOOL requestSeen = CEOrphanRecentDetailRequestForConversationSince(conversationID, selectedAt);
    BOOL resumeSeen = CEOrphanRecentResumeRequestSince(selectedAt);
    BOOL contextChanged = contextBefore.length && ![conversationID isEqualToString:contextBefore];
    BOOL sameContextResume = contextBefore.length && [conversationID isEqualToString:contextBefore] && resumeSeen;
    CERecoveryDiagnosticLog(@"HISTORY-SELECT", @"confirm index=%ld:%ld before=%@ context=%@ requestSeen=%@ resumeSeen=%@ contextChanged=%@", (long)indexPath.section, (long)indexPath.item, contextBefore ?: @"<nil>", conversationID, requestSeen ? @"YES" : @"NO", resumeSeen ? @"YES" : @"NO", contextChanged ? @"YES" : @"NO");
    if (!requestSeen && !contextChanged && !sameContextResume) return;
    CEOrphanConfirmedHistoryConversationID = conversationID;
    CEOrphanConfirmedHistoryIndexPath = [indexPath copy];
    CEOrphanConfirmedHistoryAt = NSDate.date;
    CEOrphanConfirmedHistoryCollection = collection;
    CEOrphanConfirmedHistorySource = requestSeen ? @"officialDetailRequest" : (contextChanged ? @"contextChange" : @"sameConversationResume");
    CEOrphanConfirmedHistoryStrong = YES;
    CERecoveryDiagnosticLog(@"HISTORY-SELECT", @"CONFIRMED conversation=%@ index=%ld:%ld source=%@ strong=YES", conversationID, (long)indexPath.section, (long)indexPath.item, CEOrphanConfirmedHistorySource);
}

static void CEOrphanHistoryDidSelect(id self, SEL _cmd, UICollectionView *collection, NSIndexPath *indexPath) {
    NSString *contextBefore = [[CEConversationContext shared].conversationID copy];
    NSDate *selectedAt = NSDate.date;
    NSUInteger generation = ++CEOrphanHistorySelectionGeneration;
    CERecoveryDiagnosticMark(@"OFFICIAL HISTORY ROW SELECTED");
    CERecoveryDiagnosticLog(@"HISTORY-SELECT", @"didSelect index=%ld:%ld contextBefore=%@ collection=%@ dataSource=%@", (long)indexPath.section, (long)indexPath.item, contextBefore ?: @"<nil>", NSStringFromClass(collection.class), collection.dataSource ? NSStringFromClass([(id)collection.dataSource class]) : @"<nil>");
    if (CEOrphanOriginalHistoryDidSelectIMP) ((void (*)(id, SEL, id, id))CEOrphanOriginalHistoryDidSelectIMP)(self, _cmd, collection, indexPath);
    for (NSNumber *delayValue in @[@0.20, @0.55, @1.10, @1.80, @2.60, @4.50]) {
        NSTimeInterval delay = delayValue.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanConfirmHistorySelection(collection, indexPath, contextBefore, selectedAt, generation); });
    }
}

static void CEOrphanInstallHistorySelectionCapture(NSUInteger attempt) {
    if (CEOrphanHistorySelectionHookInstalled) return;
    Class cls = NSClassFromString(@"ChatGPTHistory.HistoryViewController");
    SEL selector = NSSelectorFromString(@"collectionView:didSelectItemAtIndexPath:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (method) {
        CEOrphanOriginalHistoryDidSelectIMP = method_getImplementation(method);
        method_setImplementation(method, (IMP)CEOrphanHistoryDidSelect);
        CEOrphanHistorySelectionHookInstalled = YES;
        CERecoveryDiagnosticLog(@"HISTORY-HOOK", @"installed passive capture class=%@ selector=%@ originalIMP=%p", NSStringFromClass(cls), NSStringFromSelector(selector), CEOrphanOriginalHistoryDidSelectIMP);
        return;
    }
    if (attempt >= 20) { CERecoveryDiagnosticLog(@"HISTORY-HOOK", @"unavailable after %lu attempts", (unsigned long)attempt); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanInstallHistorySelectionCapture(attempt + 1); });
}

BOOL CEOrphanReselectConversation(NSString *conversationID) {
    CEOrphanLastSoftRefreshState = @"blocked: programmatic history reselect disabled";
    CERecoveryDiagnosticMark(@"NAVIGATION SAFETY GUARD");
    CERecoveryDiagnosticLog(@"NAV-GUARD", @"blocked CEOrphanReselectConversation conversation=%@", conversationID ?: @"<nil>");
    return NO;
}

void CEOrphanRefreshConversation(NSString *conversationID, void (^completion)(BOOL success)) {
    CEOrphanLastSoftRefreshState = @"blocked: route/history refresh disabled";
    CERecoveryDiagnosticMark(@"NAVIGATION SAFETY GUARD");
    CERecoveryDiagnosticLog(@"NAV-GUARD", @"blocked CEOrphanRefreshConversation conversation=%@", conversationID ?: @"<nil>");
    if (completion) completion(NO);
}

void CEOrphanForceReloadConversation(NSString *conversationID, void (^completion)(BOOL success)) {
    CEOrphanLastManualReloadState = @"blocked: destructive full reload disabled";
    CERecoveryDiagnosticMark(@"NAVIGATION SAFETY GUARD");
    CERecoveryDiagnosticLog(@"NAV-GUARD", @"blocked CEOrphanForceReloadConversation conversation=%@", conversationID ?: @"<nil>");
    if (completion) completion(NO);
}

NSString *CEOrphanedConversationRecoveryDiagnosticsSnapshot(void) {
    UIWindow *window = CEKeyWindow();
    UIViewController *history = window ? CEOrphanFindHistoryController(window.rootViewController, 0) : nil;
    UICollectionView *collection = history ? CEOrphanFindHistoryCollection(history.viewIfLoaded, 0) : nil;
    id dataSource = collection.dataSource;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"navigationRecoveryEnabled=NO\nrouteReplayEnabled=NO\nhistoryReplayEnabled=NO\nsidebarAutomationEnabled=NO\nhookInstalled=%@ originalIMP=%p\nlastManualReloadState=%@\nlastSoftRefreshState=%@\nlastNativeReplayState=%@\nlastTargetSource=%@\nconfirmedConversation=%@\nconfirmedIndex=%@\nconfirmedAge=%.3fs\nconfirmedSameCollection=%@\nconfirmedSource=%@\nconfirmedStrong=%@\nlastSidebarCandidate=%@\nwindow=%@\nhistoryController=%@ viewLoaded=%@ viewWindow=%@\ncollection=%@ dataSource=%@ sections=%ld selected=%@\ncontextConversation=%@",
        CEOrphanHistorySelectionHookInstalled ? @"YES" : @"NO",
        CEOrphanOriginalHistoryDidSelectIMP,
        CEOrphanLastManualReloadState ?: @"<nil>",
        CEOrphanLastSoftRefreshState ?: @"<nil>",
        CEOrphanLastNativeReplayState ?: @"<nil>",
        CEOrphanLastTargetSource ?: @"<nil>",
        CEOrphanConfirmedHistoryConversationID ?: @"<nil>",
        CEOrphanConfirmedHistoryIndexPath ? [NSString stringWithFormat:@"%ld:%ld", (long)CEOrphanConfirmedHistoryIndexPath.section, (long)CEOrphanConfirmedHistoryIndexPath.item] : @"<nil>",
        CEOrphanConfirmedHistoryAt ? [NSDate.date timeIntervalSinceDate:CEOrphanConfirmedHistoryAt] : -1.0,
        (CEOrphanConfirmedHistoryCollection && CEOrphanConfirmedHistoryCollection == collection) ? @"YES" : @"NO",
        CEOrphanConfirmedHistorySource ?: @"<nil>",
        CEOrphanConfirmedHistoryStrong ? @"YES" : @"NO",
        CEOrphanLastSidebarCandidate ?: @"<nil>",
        window ? NSStringFromClass(window.class) : @"<nil>",
        history ? NSStringFromClass(history.class) : @"<nil>",
        history.viewIfLoaded ? @"YES" : @"NO",
        history.viewIfLoaded.window ? @"YES" : @"NO",
        collection ? NSStringFromClass(collection.class) : @"<nil>",
        dataSource ? NSStringFromClass([dataSource class]) : @"<nil>",
        collection ? (long)collection.numberOfSections : -1L,
        collection ? CEOrphanIndexPathsDescription(collection.indexPathsForSelectedItems) : @"<nil>",
        [CEConversationContext shared].conversationID ?: @"<nil>"];
    return out;
}

__attribute__((constructor)) static void CEOrphanedConversationRecoveryEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CEOrphanInstallHistorySelectionCapture(0);
            CERecoveryDiagnosticLog(@"NAV-GUARD", @"programmatic route/history/sidebar recovery permanently disabled");
        });
    }
}
