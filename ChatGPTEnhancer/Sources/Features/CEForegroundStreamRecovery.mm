#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
#import "../Storage/CECatalog.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "CEForegroundStreamRecovery.h"

static const void *CERecoveryTaskFirstResumeDateKey = &CERecoveryTaskFirstResumeDateKey;
static NSDate *CERecoveryBackgroundDate = nil;
static NSString *CERecoveryConversationID = nil;
static NSUInteger CERecoveryGeneration = 0;
static BOOL CERecoveryHadStreamAtBackground = NO;
static NSHashTable<NSURLSessionTask *> *CERecoveryTrackedStreamTasks = nil;
static NSString *CERecoveryLastServerSummary = nil;
static NSString *CERecoveryLastManualPullSummary = nil;
static NSDate *CERecoveryLastForegroundDate = nil;
static NSString *CERecoveryLastSafetyState = @"navigation recovery disabled";

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
    NSUInteger textChars = 0; for (id part in parts) if ([part isKindOfClass:NSString.class]) textChars += [(NSString *)part length];
    return [NSString stringWithFormat:@"bytes=%lu rootID=%@ currentNode=%@ mapping=%lu messageID=%@ role=%@ status=%@ endTurn=%@ contentType=%@ parts=%lu textChars=%lu rootUpdate=%@ create=%@ finish=%@",
        (unsigned long)data.length,
        [container[@"id"] isKindOfClass:NSString.class] ? container[@"id"] : ([container[@"conversation_id"] isKindOfClass:NSString.class] ? container[@"conversation_id"] : @"<nil>"),
        currentNode ?: @"<nil>", (unsigned long)mapping.count,
        [message[@"id"] isKindOfClass:NSString.class] ? message[@"id"] : @"<nil>",
        [author[@"role"] isKindOfClass:NSString.class] ? author[@"role"] : @"<nil>",
        [message[@"status"] isKindOfClass:NSString.class] ? message[@"status"] : @"<nil>",
        [message[@"end_turn"] isKindOfClass:NSNumber.class] ? [message[@"end_turn"] stringValue] : @"<nil>",
        [content[@"content_type"] isKindOfClass:NSString.class] ? content[@"content_type"] : @"<nil>",
        (unsigned long)parts.count, (unsigned long)textChars,
        [container[@"update_time"] description] ?: @"<nil>", [message[@"create_time"] description] ?: @"<nil>", [metadata[@"finish_time"] description] ?: @"<nil>"];
}

static BOOL CERecoveryTimestampNearOrAfter(NSNumber *value, NSDate *cutoff) {
    if (!value || !cutoff) return NO;
    NSTimeInterval timestamp = value.doubleValue; if (timestamp > 100000000000.0) timestamp /= 1000.0;
    return timestamp >= cutoff.timeIntervalSince1970 - 5.0;
}

static BOOL CERecoveryConversationFinished(NSData *data, NSDate *cutoff, BOOL *serverAdvanced) {
    if (serverAdvanced) *serverAdvanced = NO;
    if (!data.length) return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *root = (NSDictionary *)json;
    NSDictionary *container = [root[@"conversation"] isKindOfClass:NSDictionary.class] ? root[@"conversation"] : root;
    NSString *currentNode = [container[@"current_node"] isKindOfClass:NSString.class] ? container[@"current_node"] : nil;
    NSDictionary *mapping = [container[@"mapping"] isKindOfClass:NSDictionary.class] ? container[@"mapping"] : nil;
    NSDictionary *node = currentNode.length && mapping && [mapping[currentNode] isKindOfClass:NSDictionary.class] ? mapping[currentNode] : nil;
    NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
    NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : nil;
    NSString *role = [author[@"role"] isKindOfClass:NSString.class] ? [author[@"role"] lowercaseString] : @"";
    NSString *status = [message[@"status"] isKindOfClass:NSString.class] ? [message[@"status"] lowercaseString] : @"";
    NSNumber *endTurn = [message[@"end_turn"] isKindOfClass:NSNumber.class] ? message[@"end_turn"] : nil;
    BOOL finished = [role isEqualToString:@"assistant"] && (endTurn.boolValue || [status containsString:@"finished"] || [status containsString:@"complete"] || [status containsString:@"success"] || [status isEqualToString:@"done"]);
    if (!finished) return NO;
    if (serverAdvanced && cutoff) {
        NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : nil;
        NSNumber *rootUpdate = [container[@"update_time"] isKindOfClass:NSNumber.class] ? container[@"update_time"] : nil;
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

static void CERecoveryCancelStreams(NSDate *cutoff, BOOL requireStartedBeforeCutoff, NSString *reason, void (^completion)(NSUInteger cancelled)) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!session) { if (completion) completion(0); return; }
    [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
        __block NSUInteger cancelled = 0;
        for (NSURLSessionTask *task in tasks) {
            if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
            NSURLRequest *request = task.currentRequest ?: task.originalRequest;
            if (!CERecoveryLooksLikeConversationStream(request)) continue;
            NSDate *firstResume = objc_getAssociatedObject(task, CERecoveryTaskFirstResumeDateKey);
            if (requireStartedBeforeCutoff && (!cutoff || !firstResume || [firstResume compare:cutoff] == NSOrderedDescending)) continue;
            CERecoveryDiagnosticLog(@"STREAM-CANCEL", @"reason=%@ task=%@ state=%@ path=%@ firstResume=%@", reason ?: @"<nil>", NSStringFromClass(task.class), CERecoveryTaskStateName(task.state), request.URL.path ?: @"<nil>", firstResume ?: (id)@"<nil>");
            [task cancel]; cancelled++;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(cancelled); });
    }];
}

static void CERecoveryCheckServer(NSString *conversationID, NSDate *cutoff, BOOL hadStreamAtBackground, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    CERecoveryDiagnosticLog(@"AUTO-CHECK", @"attempt=%lu conversation=%@ cutoff=%@ hadStream=%@ apiReady=%@", (unsigned long)attempt, conversationID, cutoff ?: (id)@"<nil>", hadStreamAtBackground ? @"YES" : @"NO", [[CEAPIClient shared] isReady] ? @"YES" : @"NO");
    if (![[CEAPIClient shared] isReady]) {
        if (attempt < 3) { NSTimeInterval delay = attempt == 0 ? 0.8 : attempt == 1 ? 1.5 : 3.0; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, attempt + 1); }); }
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", conversationID];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        CERecoveryLastServerSummary = CERecoveryConversationSummary(data);
        CERecoveryDiagnosticLog(@"AUTO-CHECK", @"response status=%ld error=%@ %@", (long)response.statusCode, error.localizedDescription ?: @"<nil>", CERecoveryLastServerSummary ?: @"<nil>");
        BOOL serverAdvanced = NO;
        BOOL finished = !error && response.statusCode >= 200 && response.statusCode < 300 && CERecoveryConversationFinished(data, cutoff, &serverAdvanced);
        if (finished) {
            BOOL shouldRecover = hadStreamAtBackground || serverAdvanced;
            CERecoveryDiagnosticLog(@"AUTO-CHECK", @"finished=YES serverAdvanced=%@ shouldRecover=%@ navigationRecovery=NO", serverAdvanced ? @"YES" : @"NO", shouldRecover ? @"YES" : @"NO");
            if (!shouldRecover) return;
            CERecoveryCancelStreams(cutoff, YES, @"foreground-stale-stream", ^(NSUInteger cancelled) {
                CERecoveryLastSafetyState = cancelled ? [NSString stringWithFormat:@"foreground cancelled %lu stale stream task(s); no navigation", (unsigned long)cancelled] : @"foreground server advanced; no stale stream; navigation intentionally suppressed";
                CERecoveryDiagnosticLog(@"NAV-GUARD", @"foreground conversation=%@ cancelled=%lu; route/history replay suppressed", conversationID, (unsigned long)cancelled);
            });
            return;
        }
        if (attempt < 3) { NSTimeInterval delay = attempt == 0 ? 1.0 : attempt == 1 ? 2.0 : 4.0; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, attempt + 1); }); }
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
    CERecoveryDiagnosticMark(@"MANUAL PULL LATEST SAFE");
    CERecoveryDiagnosticLog(@"PULL", @"safe fetch start conversation=%@ appState=%ld apiReady=%@ navigationRecovery=NO", conversationID ?: @"<nil>", (long)UIApplication.sharedApplication.applicationState, [[CEAPIClient shared] isReady] ? @"YES" : @"NO");
    if (!conversationID.length) { CEShowMessage(@"无法识别当前会话。"); return; }
    if (![[CEAPIClient shared] isReady]) { CEShowMessage(@"官方网络会话尚未就绪。"); return; }
    CEShowMessage(@"正在拉取最新消息…");
    NSString *encoded = [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", encoded];
    [[CEAPIClient shared] getPath:path progress:^(NSString *message) { if (message.length) CEShowMessage(message); } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        CERecoveryLastManualPullSummary = CERecoveryConversationSummary(data);
        CERecoveryDiagnosticLog(@"PULL", @"GET complete status=%ld error=%@ %@", (long)response.statusCode, error.localizedDescription ?: @"<nil>", CERecoveryLastManualPullSummary ?: @"<nil>");
        if (error || response.statusCode < 200 || response.statusCode >= 300 || !data.length) { CEShowMessage(error.localizedDescription.length ? error.localizedDescription : @"拉取最新消息失败。"); return; }
        NSString *origin = [CENetworkObserver shared].baseOrigin.length ? [CENetworkObserver shared].baseOrigin : @"https://ios.chat.openai.com";
        NSURL *requestURL = [NSURL URLWithString:[origin stringByAppendingString:path]];
        if (requestURL) [[CECatalog shared] ingestResponseData:data requestURL:requestURL];
        BOOL serverAdvanced = NO; BOOL finished = CERecoveryConversationFinished(data, nil, &serverAdvanced);
        if (!finished) { CEShowMessage(@"服务端仍在生成中。"); return; }
        CERecoveryCancelStreams(nil, NO, @"manual-pull-latest", ^(NSUInteger cancelled) {
            CERecoveryLastSafetyState = cancelled ? [NSString stringWithFormat:@"manual pull cancelled %lu active stream task(s); no navigation", (unsigned long)cancelled] : @"manual pull fetched latest server result; no active stream; no navigation";
            CERecoveryDiagnosticLog(@"NAV-GUARD", @"manual pull conversation=%@ cancelled=%lu; route/history replay suppressed", conversationID, (unsigned long)cancelled);
            if (cancelled) CEShowMessage(@"已拉取最新结果，已触发官方流恢复。");
            else CEShowMessage(@"已拉取服务端最新结果；为避免跳页，不再强制重载。");
        });
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
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CERecoveryDiagnosticMark(@"APP FOREGROUND");
            CERecoveryLastForegroundDate = NSDate.date;
            NSDate *cutoff = CERecoveryBackgroundDate;
            NSString *conversationID = [CERecoveryConversationID copy];
            BOOL hadStreamAtBackground = CERecoveryHadStreamAtBackground;
            NSUInteger generation = ++CERecoveryGeneration;
            CERecoveryBackgroundDate = nil; CERecoveryConversationID = nil; CERecoveryHadStreamAtBackground = NO;
            NSTimeInterval backgroundAge = cutoff ? [NSDate.date timeIntervalSinceDate:cutoff] : 0;
            CERecoveryDiagnosticLog(@"LIFECYCLE", @"foreground priorConversation=%@ backgroundDuration=%.3f hadStream=%@ generation=%lu currentContext=%@ navigationRecovery=NO", conversationID ?: @"<nil>", backgroundAge, hadStreamAtBackground ? @"YES" : @"NO", (unsigned long)generation, [CEConversationContext shared].conversationID ?: @"<nil>");
            if (!cutoff || !conversationID.length || backgroundAge < 1.0) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, 0); });
        }];
        CERecoveryDiagnosticLog(@"NAV-GUARD", @"foreground recovery installed in no-navigation mode");
    });
}

NSString *CEForegroundStreamRecoveryDiagnosticsSnapshot(void) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger tracked = 0, active = 0, streamActive = 0;
    @synchronized (CERecoveryTrackedStreamTasks) {
        NSArray<NSURLSessionTask *> *tasks = CERecoveryTrackedStreamTasks.allObjects ?: @[]; tracked = tasks.count;
        for (NSURLSessionTask *task in tasks) {
            if (task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended) active++;
            if ((task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended) && CERecoveryLooksLikeConversationStream(task.currentRequest ?: task.originalRequest)) streamActive++;
        }
    }
    [out appendFormat:@"navigationRecoveryEnabled=NO\ngeneration=%lu\nbackgroundDate=%@\nbackgroundConversation=%@\nhadStreamAtBackground=%@\nlastForegroundDate=%@\ntrackedTasks=%lu activeTracked=%lu activeStreamTracked=%lu\nlastServerSummary=%@\nlastManualPullSummary=%@\nlastSafetyState=%@",
        (unsigned long)CERecoveryGeneration, CERecoveryBackgroundDate ?: (id)@"<nil>", CERecoveryConversationID ?: @"<nil>", CERecoveryHadStreamAtBackground ? @"YES" : @"NO", CERecoveryLastForegroundDate ?: (id)@"<nil>", (unsigned long)tracked, (unsigned long)active, (unsigned long)streamActive, CERecoveryLastServerSummary ?: @"<nil>", CERecoveryLastManualPullSummary ?: @"<nil>", CERecoveryLastSafetyState ?: @"<nil>"];
    return out;
}

__attribute__((constructor)) static void CEForegroundStreamRecoveryEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryInstall(); });
    }
}
