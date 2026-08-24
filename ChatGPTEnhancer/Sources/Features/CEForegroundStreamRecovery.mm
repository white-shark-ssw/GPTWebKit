#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
#import "../Storage/CECatalog.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "CEForegroundStreamRecovery.h"
#import "CEOrphanedConversationRecovery.h"
#import <objc/runtime.h>

static const void *CERecoveryTaskFirstResumeDateKey = &CERecoveryTaskFirstResumeDateKey;
static NSDate *CERecoveryBackgroundDate = nil;
static NSString *CERecoveryConversationID = nil;
static NSUInteger CERecoveryGeneration = 0;
static BOOL CERecoveryHadStreamAtBackground = NO;
static NSHashTable<NSURLSessionTask *> *CERecoveryTrackedStreamTasks = nil;
static NSString *CERecoveryLastServerSummary = nil;
static NSString *CERecoveryLastManualPullSummary = nil;
static NSDate *CERecoveryLastForegroundDate = nil;

static NSString *CERecoveryTaskStateName(NSURLSessionTaskState state) {
    switch (state) {
        case NSURLSessionTaskStateRunning: return @"running";
        case NSURLSessionTaskStateSuspended: return @"suspended";
        case NSURLSessionTaskStateCanceling: return @"canceling";
        case NSURLSessionTaskStateCompleted: return @"completed";
    }
    return [NSString stringWithFormat:@"%ld", (long)state];
}

static NSString *CERecoveryConversationSummary(NSData *data) {
    if (!data.length) return @"data=<empty>";
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return [NSString stringWithFormat:@"jsonClass=%@ bytes=%lu", json ? NSStringFromClass([json class]) : @"<nil>", (unsigned long)data.length];
    NSDictionary *root = (NSDictionary *)json;
    NSDictionary *container = [root[@"conversation"] isKindOfClass:NSDictionary.class] ? root[@"conversation"] : root;
    NSString *currentNode = [container[@"current_node"] isKindOfClass:NSString.class] ? container[@"current_node"] : nil;
    NSDictionary *mapping = [container[@"mapping"] isKindOfClass:NSDictionary.class] ? container[@"mapping"] : nil;
    NSDictionary *node = currentNode.length && [mapping[currentNode] isKindOfClass:NSDictionary.class] ? mapping[currentNode] : nil;
    NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
    NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : nil;
    NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : nil;
    NSDictionary *content = [message[@"content"] isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    NSArray *parts = [content[@"parts"] isKindOfClass:NSArray.class] ? content[@"parts"] : nil;
    NSUInteger textChars = 0;
    for (id part in parts) if ([part isKindOfClass:NSString.class]) textChars += [(NSString *)part length];
    return [NSString stringWithFormat:@"bytes=%lu rootID=%@ currentNode=%@ mapping=%lu messageID=%@ role=%@ status=%@ endTurn=%@ contentType=%@ parts=%lu textChars=%lu rootUpdate=%@ create=%@ finish=%@",
        (unsigned long)data.length,
        [container[@"id"] isKindOfClass:NSString.class] ? container[@"id"] : ([container[@"conversation_id"] isKindOfClass:NSString.class] ? container[@"conversation_id"] : @"<nil>"),
        currentNode ?: @"<nil>",
        (unsigned long)mapping.count,
        [message[@"id"] isKindOfClass:NSString.class] ? message[@"id"] : @"<nil>",
        [author[@"role"] isKindOfClass:NSString.class] ? author[@"role"] : @"<nil>",
        [message[@"status"] isKindOfClass:NSString.class] ? message[@"status"] : @"<nil>",
        [message[@"end_turn"] isKindOfClass:NSNumber.class] ? [message[@"end_turn"] stringValue] : @"<nil>",
        [content[@"content_type"] isKindOfClass:NSString.class] ? content[@"content_type"] : @"<nil>",
        (unsigned long)parts.count,
        (unsigned long)textChars,
        [container[@"update_time"] description] ?: @"<nil>",
        [message[@"create_time"] description] ?: @"<nil>",
        [metadata[@"finish_time"] description] ?: @"<nil>"
    ];
}

static BOOL CERecoveryTimestampNearOrAfter(NSNumber *value, NSDate *cutoff) {
    if (!value || !cutoff) return NO;
    NSTimeInterval timestamp = value.doubleValue;
    if (timestamp > 100000000000.0) timestamp /= 1000.0;
    return timestamp >= cutoff.timeIntervalSince1970 - 5.0;
}

static BOOL CERecoveryConversationFinished(NSData *data, NSDate *cutoff, BOOL *serverAdvanced) {
    if (serverAdvanced) *serverAdvanced = NO;
    if (!data.length) return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *root = (NSDictionary *)json;
    NSString *currentNode = [root[@"current_node"] isKindOfClass:NSString.class] ? root[@"current_node"] : nil;
    NSDictionary *mapping = [root[@"mapping"] isKindOfClass:NSDictionary.class] ? root[@"mapping"] : nil;
    NSDictionary *node = currentNode.length && mapping ? ([mapping[currentNode] isKindOfClass:NSDictionary.class] ? mapping[currentNode] : nil) : nil;
    NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
    NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : nil;
    NSString *role = [author[@"role"] isKindOfClass:NSString.class] ? [author[@"role"] lowercaseString] : @"";
    NSString *status = [message[@"status"] isKindOfClass:NSString.class] ? [message[@"status"] lowercaseString] : @"";
    NSNumber *endTurn = [message[@"end_turn"] isKindOfClass:NSNumber.class] ? message[@"end_turn"] : nil;
    BOOL finished = [role isEqualToString:@"assistant"] && (endTurn.boolValue || [status containsString:@"finished"] || [status containsString:@"complete"] || [status containsString:@"success"] || [status isEqualToString:@"done"]);
    if (!finished) return NO;
    if (serverAdvanced && cutoff) {
        NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : nil;
        NSNumber *rootUpdate = [root[@"update_time"] isKindOfClass:NSNumber.class] ? root[@"update_time"] : nil;
        NSNumber *messageCreate = [message[@"create_time"] isKindOfClass:NSNumber.class] ? message[@"create_time"] : nil;
        NSNumber *finishTime = [metadata[@"finish_time"] isKindOfClass:NSNumber.class] ? metadata[@"finish_time"] : nil;
        *serverAdvanced = CERecoveryTimestampNearOrAfter(rootUpdate, cutoff) || CERecoveryTimestampNearOrAfter(messageCreate, cutoff) || CERecoveryTimestampNearOrAfter(finishTime, cutoff);
    }
    return YES;
}

static BOOL CERecoveryLooksLikeConversationStream(NSURLRequest *request) {
    if (!request.URL) return NO;
    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";
    NSString *path = request.URL.path.lowercaseString ?: @"";
    if (![method isEqualToString:@"POST"] || ![path containsString:@"conversation"]) return NO;
    NSArray<NSString *> *excluded = @[@"/prepare", @"/init", @"gen_title", @"feedback", @"share", @"search", @"message_feedback", @"conversation_limit"];
    for (NSString *token in excluded) if ([path containsString:token]) return NO;
    NSString *accept = [[request valueForHTTPHeaderField:@"Accept"] lowercaseString] ?: @"";
    if ([accept containsString:@"text/event-stream"]) return YES;
    if ([path hasSuffix:@"/backend-api/conversation"] || [path hasSuffix:@"/backend-api/f/conversation"]) return YES;
    return [path containsString:@"/conversation/stream"] || [path containsString:@"/f/conversation/"];
}

static void CERecoveryTrackStreamTask(NSURLSessionTask *task) {
    if (!task) return;
    NSURLRequest *request = task.currentRequest ?: task.originalRequest;
    if (!CERecoveryLooksLikeConversationStream(request)) return;
    CERecoveryDiagnosticLog(@"STREAM", @"track task=%@ state=%@ method=%@ path=%@", NSStringFromClass(task.class), CERecoveryTaskStateName(task.state), request.HTTPMethod ?: @"<nil>", request.URL.path ?: @"<nil>");
    @synchronized (CERecoveryTrackedStreamTasks) {
        [CERecoveryTrackedStreamTasks addObject:task];
        if (CERecoveryBackgroundDate && UIApplication.sharedApplication.applicationState != UIApplicationStateActive) CERecoveryHadStreamAtBackground = YES;
    }
}

static BOOL CERecoveryHasActiveTrackedStream(void) {
    BOOL found = NO;
    @synchronized (CERecoveryTrackedStreamTasks) {
        for (NSURLSessionTask *task in CERecoveryTrackedStreamTasks.allObjects) {
            if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
            if (CERecoveryLooksLikeConversationStream(task.currentRequest ?: task.originalRequest)) { found = YES; break; }
        }
    }
    return found;
}

static void CERecoveryForceConversationReloadAttempt(NSString *conversationID, NSUInteger generation, NSUInteger attempt) {
    if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { CERecoveryDiagnosticLog(@"AUTO-RELOAD", @"skip generation=%lu currentGeneration=%lu appState=%ld", (unsigned long)generation, (unsigned long)CERecoveryGeneration, (long)UIApplication.sharedApplication.applicationState); return; }
    CERecoveryDiagnosticLog(@"AUTO-RELOAD", @"attempt=%lu conversation=%@ phase=soft-refresh", (unsigned long)attempt, conversationID);
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    CEOrphanRefreshConversation(conversationID, ^(BOOL success) {
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        if (success) {
            CERecoveryDiagnosticLog(@"AUTO-RELOAD", @"soft refresh triggered official request conversation=%@", conversationID);
            NSLog(@"[ChatGPTEnhancer] foreground recovery triggered lightweight refresh for %@", conversationID);
            return;
        }
        CERecoveryDiagnosticLog(@"AUTO-RELOAD", @"soft refresh unavailable; trying full history replay conversation=%@", conversationID);
        if (CEOrphanReselectConversation(conversationID)) {
            CERecoveryDiagnosticLog(@"AUTO-RELOAD", @"full replay invoked conversation=%@", conversationID);
            NSLog(@"[ChatGPTEnhancer] foreground recovery forced completed conversation reload for %@", conversationID);
            return;
        }
        CERecoveryDiagnosticLog(@"AUTO-RELOAD", @"full replay returned NO conversation=%@ attempt=%lu", conversationID, (unsigned long)attempt);
        if (attempt >= 1) { NSLog(@"[ChatGPTEnhancer] foreground recovery could not refresh completed conversation %@", conversationID); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryForceConversationReloadAttempt(conversationID, generation, attempt + 1); });
    });
}

static void CERecoveryForceConversationReload(NSString *conversationID, NSUInteger generation, NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryForceConversationReloadAttempt(conversationID, generation, 0); });
}

static void CERecoveryCancelStaleStreamTasks(NSDate *cutoff, NSString *conversationID, NSUInteger generation, BOOL forceReload, void (^completion)(NSUInteger cancelled)) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!cutoff || !conversationID.length) { CERecoveryDiagnosticLog(@"STREAM-CANCEL", @"invalid input cutoff=%@ conversation=%@", cutoff ?: (id)@"<nil>", conversationID ?: @"<nil>"); if (completion) completion(0); return; }
    CERecoveryDiagnosticLog(@"STREAM-CANCEL", @"begin conversation=%@ session=%@ forceReload=%@", conversationID, session ? NSStringFromClass(session.class) : @"<nil>", forceReload ? @"YES" : @"NO");
    if (!session) {
        if (forceReload) CERecoveryForceConversationReload(conversationID, generation, 0.15);
        if (completion) completion(0);
        return;
    }
    [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
        __block NSUInteger cancelled = 0;
        for (NSURLSessionTask *task in tasks) {
            if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
            NSDate *firstResume = objc_getAssociatedObject(task, CERecoveryTaskFirstResumeDateKey);
            if (!firstResume || [firstResume compare:cutoff] == NSOrderedDescending) continue;
            NSURLRequest *request = task.currentRequest ?: task.originalRequest;
            if (!CERecoveryLooksLikeConversationStream(request)) continue;
            CERecoveryDiagnosticLog(@"STREAM-CANCEL", @"cancel task=%@ state=%@ method=%@ path=%@ firstResume=%@", NSStringFromClass(task.class), CERecoveryTaskStateName(task.state), request.HTTPMethod ?: @"<nil>", request.URL.path ?: @"<nil>", firstResume ?: (id)@"<nil>");
            [task cancel]; cancelled++;
            NSLog(@"[ChatGPTEnhancer] foreground recovery cancelled stale stream task %@ %@ started=%@", request.HTTPMethod ?: @"", request.URL.path ?: @"", firstResume);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            CERecoveryDiagnosticLog(@"STREAM-CANCEL", @"complete conversation=%@ cancelled=%lu", conversationID, (unsigned long)cancelled);
            if (cancelled) NSLog(@"[ChatGPTEnhancer] foreground recovery triggered official stream recovery for %@ (%lu stale task%@)", conversationID, (unsigned long)cancelled, cancelled == 1 ? @"" : @"s");
            else NSLog(@"[ChatGPTEnhancer] foreground recovery server is complete for %@ but no stale stream task remained", conversationID);
            if (forceReload) CERecoveryForceConversationReload(conversationID, generation, cancelled ? 0.55 : 0.15);
            if (completion) completion(cancelled);
        });
    }];
}

static void CERecoveryCheckServer(NSString *conversationID, NSDate *cutoff, BOOL hadStreamAtBackground, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { CERecoveryDiagnosticLog(@"AUTO-CHECK", @"skip conversation=%@ generation=%lu current=%lu appState=%ld", conversationID ?: @"<nil>", (unsigned long)generation, (unsigned long)CERecoveryGeneration, (long)UIApplication.sharedApplication.applicationState); return; }
    CERecoveryDiagnosticLog(@"AUTO-CHECK", @"attempt=%lu conversation=%@ cutoff=%@ hadStreamAtBackground=%@ apiReady=%@", (unsigned long)attempt, conversationID, cutoff ?: (id)@"<nil>", hadStreamAtBackground ? @"YES" : @"NO", [[CEAPIClient shared] isReady] ? @"YES" : @"NO");
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    if (![[CEAPIClient shared] isReady]) {
        if (attempt < 3) {
            NSTimeInterval delay = attempt == 0 ? 0.8 : attempt == 1 ? 1.5 : 3.0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, attempt + 1); });
        }
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", conversationID];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { CERecoveryDiagnosticLog(@"AUTO-CHECK", @"response ignored generation/appState"); return; }
        CERecoveryLastServerSummary = CERecoveryConversationSummary(data);
        CERecoveryDiagnosticLog(@"AUTO-CHECK", @"response status=%ld error=%@ %@", (long)response.statusCode, error.localizedDescription ?: @"<nil>", CERecoveryLastServerSummary ?: @"<nil>");
        BOOL serverAdvanced = NO;
        if (!error && response.statusCode >= 200 && response.statusCode < 300 && CERecoveryConversationFinished(data, cutoff, &serverAdvanced)) {
            BOOL forceReload = hadStreamAtBackground || serverAdvanced;
            CERecoveryDiagnosticLog(@"AUTO-CHECK", @"finished=YES serverAdvanced=%@ forceReload=%@", serverAdvanced ? @"YES" : @"NO", forceReload ? @"YES" : @"NO");
            NSLog(@"[ChatGPTEnhancer] foreground recovery server complete conversation=%@ hadStream=%@ serverAdvanced=%@ forceReload=%@", conversationID, hadStreamAtBackground ? @"YES" : @"NO", serverAdvanced ? @"YES" : @"NO", forceReload ? @"YES" : @"NO");
            CERecoveryCancelStaleStreamTasks(cutoff, conversationID, generation, forceReload, nil);
            return;
        }
        if (attempt < 3) {
            NSTimeInterval delay = attempt == 0 ? 1.0 : attempt == 1 ? 2.0 : 4.0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, attempt + 1); });
        }
    }];
}

@interface NSURLSessionTask (ChatGPTEnhancerForegroundRecovery)
- (void)ce_recovery_resume;
@end

@implementation NSURLSessionTask (ChatGPTEnhancerForegroundRecovery)
- (void)ce_recovery_resume {
    if (!objc_getAssociatedObject(self, CERecoveryTaskFirstResumeDateKey)) objc_setAssociatedObject(self, CERecoveryTaskFirstResumeDateKey, NSDate.date, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CERecoveryTrackStreamTask(self);
    [self ce_recovery_resume];
}
@end

void CEPullLatestConversationResult(NSString *conversationID) {
    CERecoveryDiagnosticMark(@"MANUAL PULL LATEST");
    CERecoveryDiagnosticLog(@"PULL", @"start conversation=%@ appState=%ld apiReady=%@ session=%@ template=%@", conversationID ?: @"<nil>", (long)UIApplication.sharedApplication.applicationState, [[CEAPIClient shared] isReady] ? @"YES" : @"NO", [CENetworkObserver shared].requestSession ? NSStringFromClass([CENetworkObserver shared].requestSession.class) : @"<nil>", [CENetworkObserver shared].hasUsableTemplate ? @"YES" : @"NO");
    if (!conversationID.length) { CERecoveryDiagnosticLog(@"PULL", @"abort missing conversation id"); CEShowMessage(@"无法识别当前会话。"); return; }
    if (![[CEAPIClient shared] isReady]) { CERecoveryDiagnosticLog(@"PULL", @"abort API client not ready"); CEShowMessage(@"官方网络会话尚未就绪。"); return; }
    CEShowMessage(@"正在拉取最新消息…");
    NSString *encoded = [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", encoded];
    [[CEAPIClient shared] getPath:path progress:^(NSString *message) { if (message.length) { CERecoveryDiagnosticLog(@"PULL", @"progress=%@", message); CEShowMessage(message); } } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        CERecoveryLastManualPullSummary = CERecoveryConversationSummary(data);
        CERecoveryDiagnosticLog(@"PULL", @"GET complete status=%ld error=%@ %@", (long)response.statusCode, error.localizedDescription ?: @"<nil>", CERecoveryLastManualPullSummary ?: @"<nil>");
        if (error || response.statusCode < 200 || response.statusCode >= 300 || !data.length) { CEShowMessage(error.localizedDescription.length ? error.localizedDescription : @"拉取最新消息失败。"); return; }
        NSString *origin = [CENetworkObserver shared].baseOrigin.length ? [CENetworkObserver shared].baseOrigin : @"https://ios.chat.openai.com";
        NSURL *requestURL = [NSURL URLWithString:[origin stringByAppendingString:path]];
        if (requestURL) [[CECatalog shared] ingestResponseData:data requestURL:requestURL];
        BOOL serverAdvanced = NO;
        BOOL finished = CERecoveryConversationFinished(data, nil, &serverAdvanced);
        CERecoveryDiagnosticLog(@"PULL", @"serverFinished=%@", finished ? @"YES" : @"NO");
        if (!finished) { CEShowMessage(@"服务端仍在生成中。"); return; }
        void (^trySoftRefresh)(void) = ^{
            CERecoveryDiagnosticLog(@"PULL", @"no recoverable stream remains; trying lightweight official conversation refresh");
            CEOrphanRefreshConversation(conversationID, ^(BOOL success) {
                CERecoveryDiagnosticLog(@"PULL", @"lightweight refresh result=%@", success ? @"YES" : @"NO");
                if (success) CEShowMessage(@"已拉取最新结果，正在刷新当前会话…");
                else CEShowMessage(@"已拉取最新结果；轻量刷新未触发，可使用“重载当前会话”。");
            });
        };
        NSURLSession *session = [CENetworkObserver shared].requestSession;
        if (!session) { trySoftRefresh(); return; }
        [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
            __block NSUInteger cancelled = 0, active = 0, streamCandidates = 0;
            CERecoveryDiagnosticLog(@"PULL", @"session tasks total=%lu", (unsigned long)tasks.count);
            for (NSURLSessionTask *task in tasks) {
                if (task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended) active++;
                NSURLRequest *candidateRequest = task.currentRequest ?: task.originalRequest;
                if (CERecoveryLooksLikeConversationStream(candidateRequest)) {
                    streamCandidates++;
                    CERecoveryDiagnosticLog(@"PULL-TASK", @"task=%@ state=%@ method=%@ path=%@ firstResume=%@", NSStringFromClass(task.class), CERecoveryTaskStateName(task.state), candidateRequest.HTTPMethod ?: @"<nil>", candidateRequest.URL.path ?: @"<nil>", objc_getAssociatedObject(task, CERecoveryTaskFirstResumeDateKey) ?: (id)@"<nil>");
                }
                if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
                NSURLRequest *request = task.currentRequest ?: task.originalRequest;
                if (!CERecoveryLooksLikeConversationStream(request)) continue;
                [task cancel]; cancelled++;
            }
            CERecoveryDiagnosticLog(@"PULL", @"task scan active=%lu streamCandidates=%lu cancelled=%lu", (unsigned long)active, (unsigned long)streamCandidates, (unsigned long)cancelled);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (cancelled) {
                    CEShowMessage(@"已拉取最新结果，正在同步…");
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), trySoftRefresh);
                } else {
                    trySoftRefresh();
                }
            });
        }];
    }];
}

static void CERecoveryInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CERecoveryTrackedStreamTasks = [NSHashTable weakObjectsHashTable];
        CESwizzleInstanceMethod(NSURLSessionTask.class, @selector(resume), @selector(ce_recovery_resume));
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CERecoveryDiagnosticMark(@"APP BACKGROUND");
            CERecoveryBackgroundDate = NSDate.date;
            CERecoveryConversationID = [[CEConversationContext shared].conversationID copy];
            CERecoveryHadStreamAtBackground = CERecoveryHasActiveTrackedStream();
            CERecoveryGeneration++;
            CERecoveryDiagnosticLog(@"LIFECYCLE", @"background conversation=%@ activeTrackedStream=%@ generation=%lu", CERecoveryConversationID ?: @"<nil>", CERecoveryHadStreamAtBackground ? @"YES" : @"NO", (unsigned long)CERecoveryGeneration);
            NSLog(@"[ChatGPTEnhancer] foreground recovery background snapshot conversation=%@ activeStream=%@", CERecoveryConversationID ?: @"<nil>", CERecoveryHadStreamAtBackground ? @"YES" : @"NO");
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CERecoveryDiagnosticMark(@"APP FOREGROUND");
            CERecoveryLastForegroundDate = NSDate.date;
            NSDate *cutoff = CERecoveryBackgroundDate;
            NSString *conversationID = [CERecoveryConversationID copy];
            BOOL hadStreamAtBackground = CERecoveryHadStreamAtBackground;
            NSUInteger generation = ++CERecoveryGeneration;
            CERecoveryBackgroundDate = nil;
            CERecoveryConversationID = nil;
            CERecoveryHadStreamAtBackground = NO;
            NSTimeInterval backgroundAge = cutoff ? [NSDate.date timeIntervalSinceDate:cutoff] : 0;
            CERecoveryDiagnosticLog(@"LIFECYCLE", @"foreground priorConversation=%@ backgroundDuration=%.3f hadStream=%@ generation=%lu currentContext=%@", conversationID ?: @"<nil>", backgroundAge, hadStreamAtBackground ? @"YES" : @"NO", (unsigned long)generation, [CEConversationContext shared].conversationID ?: @"<nil>");
            if (!cutoff || !conversationID.length || backgroundAge < 1.0) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, 0); });
        }];
        NSLog(@"[ChatGPTEnhancer] foreground stream recovery installed");
    });
}

NSString *CEForegroundStreamRecoveryDiagnosticsSnapshot(void) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger tracked = 0, active = 0, streamActive = 0;
    @synchronized (CERecoveryTrackedStreamTasks) {
        NSArray<NSURLSessionTask *> *tasks = CERecoveryTrackedStreamTasks.allObjects ?: @[];
        tracked = tasks.count;
        for (NSURLSessionTask *task in tasks) {
            if (task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended) active++;
            if ((task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended) && CERecoveryLooksLikeConversationStream(task.currentRequest ?: task.originalRequest)) streamActive++;
        }
    }
    [out appendFormat:@"generation=%lu\nbackgroundDate=%@\nbackgroundConversation=%@\nhadStreamAtBackground=%@\nlastForegroundDate=%@\ntrackedTasks=%lu activeTracked=%lu activeStreamTracked=%lu\nlastServerSummary=%@\nlastManualPullSummary=%@",
        (unsigned long)CERecoveryGeneration,
        CERecoveryBackgroundDate ?: (id)@"<nil>",
        CERecoveryConversationID ?: @"<nil>",
        CERecoveryHadStreamAtBackground ? @"YES" : @"NO",
        CERecoveryLastForegroundDate ?: (id)@"<nil>",
        (unsigned long)tracked,
        (unsigned long)active,
        (unsigned long)streamActive,
        CERecoveryLastServerSummary ?: @"<nil>",
        CERecoveryLastManualPullSummary ?: @"<nil>"];
    return out;
}

__attribute__((constructor)) static void CEForegroundStreamRecoveryEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryInstall(); });
    }
}
