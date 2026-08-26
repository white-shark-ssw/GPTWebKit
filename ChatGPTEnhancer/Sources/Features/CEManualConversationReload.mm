#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CEManualConversationReload.h"
#import "../Core/CECore.h"
#import "../Network/CENetworkObserver.h"
#import "../UI/CEEnhancerUI.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "../Diagnostics/CEConversationIdentityTrace.h"

static NSUInteger CEManualReloadGeneration = 0;
static BOOL CEManualReloadInFlight = NO;
static NSString *CEManualReloadTargetID = nil;
static NSDate *CEManualReloadStartedAt = nil;
static NSObject *CEManualReloadBaselineUISnapshot = nil;
static BOOL CEManualReloadBaselineHadContent = NO;
static BOOL CEManualReloadRequestObserved = NO;
static BOOL CEManualReloadUIRebuildObserved = NO;
static BOOL CEManualReloadUISawContentDisappear = NO;

static BOOL CEManualReloadRequestSeen(NSString *conversationID, NSDate *since, NSString **sourceOut) {
    if (!conversationID.length || !since) return NO;
    long long threshold = (long long)(since.timeIntervalSince1970 * 1000.0); NSString *cid = conversationID.lowercaseString;
    for (NSString *event in [CENetworkObserver shared].recentEvents.reverseObjectEnumerator) {
        long long timestamp = event.longLongValue; if (timestamp && timestamp < threshold) break;
        NSString *lower = event.lowercaseString; if (![lower containsString:@" req "]) continue;
        if ([lower containsString:[NSString stringWithFormat:@"/backend-api/conversation/%@", cid]] || [lower containsString:[NSString stringWithFormat:@"/backend-api/f/conversation/%@", cid]]) { if (sourceOut) *sourceOut = @"detail"; return YES; }
        if ([lower containsString:@" req post "] && [lower containsString:@"/backend-api/f/conversation/resume"]) { if (sourceOut) *sourceOut = @"resume"; return YES; }
    }
    return NO;
}

static NSURL *CEManualReloadRouteURL(NSString *conversationID, NSUInteger routeAttempt, NSString *nonce) {
    if (!conversationID.length) return nil;
    NSString *escaped = [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    if (routeAttempt == 0) return [NSURL URLWithString:[NSString stringWithFormat:@"com.openai.chat://chatgpt.com/c/%@/", escaped]];
    if (routeAttempt == 1) return [NSURL URLWithString:[NSString stringWithFormat:@"com.openai.chat://chatgpt.com/c/%@/?ce_reload=%@", escaped, nonce]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"com.openai.chat://chatgpt.com/c/%@?ce_reload=%@-%lu", escaped, nonce, (unsigned long)routeAttempt]];
}

static void CEManualReloadFinish(NSUInteger generation, BOOL success, NSString *message) {
    if (generation != CEManualReloadGeneration) return;
    CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"finish generation=%lu success=%@ target=%@ requestObserved=%@ uiRebuildObserved=%@ message=%@", (unsigned long)generation, success ? @"YES" : @"NO", CEManualReloadTargetID ?: @"<none>", CEManualReloadRequestObserved ? @"YES" : @"NO", CEManualReloadUIRebuildObserved ? @"YES" : @"NO", message ?: @"<none>");
    CEManualReloadInFlight = NO; CEManualReloadTargetID = nil; CEManualReloadStartedAt = nil; CEManualReloadBaselineUISnapshot = nil; CEManualReloadBaselineHadContent = NO; CEManualReloadRequestObserved = NO; CEManualReloadUIRebuildObserved = NO; CEManualReloadUISawContentDisappear = NO;
    CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"FINISH generation=%lu success=%@ message=%@", (unsigned long)generation, success ? @"YES" : @"NO", message ?: @"<nil>");
    CEShowMessage(message ?: (success ? @"✓ 当前会话已重载" : @"重载未完成，当前页面保持不变。"));
}

static void CEManualReloadOpenAttempt(NSUInteger generation, NSString *conversationID, NSString *nonce, NSUInteger routeAttempt);

static void CEManualReloadObserveUIState(void) {
    NSObject *current = CECaptureCurrentConversationUIReloadSnapshot(); BOOL hasContent = CECurrentConversationUIReloadSnapshotHasContent(current);
    if (CEManualReloadBaselineHadContent && !hasContent) CEManualReloadUISawContentDisappear = YES;
    if (CECurrentConversationUIReloadSnapshotShowsRebuild(CEManualReloadBaselineUISnapshot, current) || (CEManualReloadUISawContentDisappear && hasContent)) CEManualReloadUIRebuildObserved = YES;
}

static void CEManualReloadVerifyAttempt(NSUInteger generation, NSString *conversationID, NSString *nonce, NSUInteger routeAttempt, NSUInteger poll) {
    if (generation != CEManualReloadGeneration || !CEManualReloadInFlight) return;
    NSString *current = [CEConversationContext shared].conversationID;
    if (!current.length || ![current isEqualToString:conversationID]) { CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"SAFETY context changed expected=%@ actual=%@", conversationID, current ?: @"<nil>"); CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"safety-context-changed expected=%@ actual=%@", conversationID, current ?: @"<none>"); CEManualReloadFinish(generation, NO, @"重载已停止：当前会话发生变化。"); return; }

    NSString *source = nil;
    if (CEManualReloadRequestSeen(conversationID, CEManualReloadStartedAt, &source)) CEManualReloadRequestObserved = YES;
    CEManualReloadObserveUIState();
    CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"verify generation=%lu routeAttempt=%lu poll=%lu target=%@ requestObserved=%@ source=%@ uiRebuildObserved=%@ uiSawDisappear=%@", (unsigned long)generation, (unsigned long)routeAttempt, (unsigned long)poll, conversationID, CEManualReloadRequestObserved ? @"YES" : @"NO", source ?: @"<none>", CEManualReloadUIRebuildObserved ? @"YES" : @"NO", CEManualReloadUISawContentDisappear ? @"YES" : @"NO");
    if (CEManualReloadRequestObserved && CEManualReloadUIRebuildObserved) { CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"SUCCESS routeAttempt=%lu poll=%lu source=%@ conversation=%@ request+ui-rebuild confirmed", (unsigned long)routeAttempt, (unsigned long)poll, source ?: @"earlier", conversationID); CEManualReloadFinish(generation, YES, @"✓ 当前会话已重载"); return; }

    NSUInteger maxPoll = routeAttempt < 2 ? 7 : 14;
    if (poll >= maxPoll) {
        if (routeAttempt < 2) {
            CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"reload not fully confirmed after routeAttempt=%lu requestObserved=%@ uiRebuildObserved=%@; retrying same exact conversation with unique route delivery", (unsigned long)routeAttempt, CEManualReloadRequestObserved ? @"YES" : @"NO", CEManualReloadUIRebuildObserved ? @"YES" : @"NO");
            CEManualReloadOpenAttempt(generation, conversationID, nonce, routeAttempt + 1); return;
        }
        if (CEManualReloadRequestObserved) { CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"FAIL request observed but current conversation UI rebuild not confirmed conversation=%@", conversationID); CEManualReloadFinish(generation, NO, @"已触发当前会话请求，但未确认页面完成刷新。"); }
        else { CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"FAIL no official detail/resume request after all exact-route attempts conversation=%@", conversationID); CEManualReloadFinish(generation, NO, @"重载未完成，当前页面保持不变。"); }
        return;
    }
    NSTimeInterval delay = routeAttempt < 2 ? 0.40 : 0.50;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEManualReloadVerifyAttempt(generation, conversationID, nonce, routeAttempt, poll + 1); });
}

static void CEManualReloadOpenAttempt(NSUInteger generation, NSString *conversationID, NSString *nonce, NSUInteger routeAttempt) {
    if (generation != CEManualReloadGeneration || !CEManualReloadInFlight) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { CEManualReloadFinish(generation, NO, @"重载已停止：App 当前不在前台。"); return; }
    NSString *current = [CEConversationContext shared].conversationID;
    if (!current.length || ![current isEqualToString:conversationID]) { CEManualReloadFinish(generation, NO, @"重载已停止：当前会话发生变化。"); return; }
    NSURL *route = CEManualReloadRouteURL(conversationID, routeAttempt, nonce);
    if (!route) { CEManualReloadFinish(generation, NO, @"重载未完成，当前页面保持不变。"); return; }
    CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"open-route generation=%lu routeAttempt=%lu target=%@ contextID=%@", (unsigned long)generation, (unsigned long)routeAttempt, conversationID, current);
    CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"OPEN generation=%lu routeAttempt=%lu conversation=%@ route=%@", (unsigned long)generation, (unsigned long)routeAttempt, conversationID, route.absoluteString);
    [UIApplication.sharedApplication openURL:route options:@{} completionHandler:^(BOOL opened) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != CEManualReloadGeneration || !CEManualReloadInFlight) return;
            CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"route-delivery generation=%lu routeAttempt=%lu opened=%@ target=%@", (unsigned long)generation, (unsigned long)routeAttempt, opened ? @"YES" : @"NO", conversationID);
            CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"DELIVER generation=%lu routeAttempt=%lu opened=%@ conversation=%@", (unsigned long)generation, (unsigned long)routeAttempt, opened ? @"YES" : @"NO", conversationID);
            if (!opened && routeAttempt < 2) { CEManualReloadOpenAttempt(generation, conversationID, nonce, routeAttempt + 1); return; }
            if (!opened) { CEManualReloadFinish(generation, NO, @"重载未完成，当前页面保持不变。"); return; }
            CEManualReloadVerifyAttempt(generation, conversationID, nonce, routeAttempt, 0);
        });
    }];
}

void CEManualReloadConversationID(NSString *conversationID) {
    conversationID = [conversationID copy]; CEConversationContext *context = [CEConversationContext shared];
    CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"exact-target requested=%@ contextID=%@ contextTitle=%@", conversationID ?: @"<none>", context.conversationID ?: @"<none>", context.title ?: @"<none>");
    if (!conversationID.length || !context.conversationID.length || ![context.conversationID isEqualToString:conversationID]) { CEShowMessage(@"当前会话已变化，已取消重载。"); return; }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { CEShowMessage(@"App 回到前台后再重载。"); return; }
    if (CEManualReloadInFlight) { if ([CEManualReloadTargetID isEqualToString:conversationID]) CEShowMessage(@"当前会话正在重载…"); else CEShowMessage(@"已有重载任务正在进行。"); return; }

    CEManualReloadInFlight = YES; CEManualReloadTargetID = conversationID; CEManualReloadStartedAt = NSDate.date; CEManualReloadBaselineUISnapshot = CECaptureCurrentConversationUIReloadSnapshot(); CEManualReloadBaselineHadContent = CECurrentConversationUIReloadSnapshotHasContent(CEManualReloadBaselineUISnapshot); CEManualReloadRequestObserved = NO; CEManualReloadUIRebuildObserved = NO; CEManualReloadUISawContentDisappear = NO; NSUInteger generation = ++CEManualReloadGeneration;
    NSString *nonce = [NSString stringWithFormat:@"%llu", (unsigned long long)(NSDate.date.timeIntervalSince1970 * 1000.0)];
    CEConversationIdentityTraceLog(@"ACTION-RELOAD", @"start generation=%lu target=%@ baselineUI=%@", (unsigned long)generation, conversationID, CEManualReloadBaselineHadContent ? @"content" : @"unproven"); CERecoveryDiagnosticMark(@"MANUAL RELOAD48 EXACT MENU TARGET + UI PROOF");
    CERecoveryDiagnosticLog(@"MANUAL-RELOAD39", @"START generation=%lu conversation=%@ appState=%ld baselineUI=%@", (unsigned long)generation, conversationID, (long)UIApplication.sharedApplication.applicationState, CEManualReloadBaselineHadContent ? @"content" : @"unproven"); CEShowMessage(@"正在重载当前会话…");
    CEManualReloadOpenAttempt(generation, conversationID, nonce, 0);
}
