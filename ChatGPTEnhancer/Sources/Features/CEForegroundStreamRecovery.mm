#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
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
static NSString *CERecoveryLastSafetyState = @"foreground checks require a tracked conversation stream";

static NSString *CERecoveryTaskStateName(NSURLSessionTaskState state) {
    switch (state) {
        case NSURLSessionTaskStateRunning: return @"running";
        case NSURLSessionTaskStateSuspended: return @"suspended";
        case NSURLSessionTaskStateCanceling: return @"canceling";
        case NSURLSessionTaskStateCompleted: return @"completed";
    }
    return [NSString stringWithFormat:@"%ld", (long)state];
}

static BOOL CERecoveryTimestampNearOrAfter(NSNumber *value, NSDate *cutoff) {
    if (!value || !cutoff) return NO;
    NSTimeInterval timestamp = value.doubleValue; if (timestamp > 100000000000.0) timestamp /= 1000.0;
    return timestamp >= cutoff.timeIntervalSince1970 - 5.0;
}

static NSDictionary *CERecoveryAnalyzeConversation(NSData *data, NSDate *cutoff) {
    if (!data.length) return @{ @"summary": @"data=<empty>", @"finished": @NO, @"serverAdvanced": @NO };
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return @{ @"summary": [NSString stringWithFormat:@"jsonClass=%@ bytes=%lu", json ? NSStringFromClass([json class]) : @"<nil>", (unsigned long)data.length], @"finished": @NO, @"serverAdvanced": @NO };
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
    NSString *role = [author[@"role"] isKindOfClass:NSString.class] ? [author[@"role"] lowercaseString] : @"";
    NSString *status = [message[@"status"] isKindOfClass:NSString.class] ? [message[@"status"] lowercaseString] : @"";
    NSNumber *endTurn = [message[@"end_turn"] isKindOfClass:NSNumber.class] ? message[@"end_turn"] : nil;
    BOOL finished = [role isEqualToString:@"assistant"] && (endTurn.boolValue || [status containsString:@"finished"] || [status containsString:@"complete"] || [status containsString:@"success"] || [status isEqualToString:@"done"]);
    BOOL serverAdvanced = NO;
    if (finished && cutoff) {
        NSNumber *rootUpdate = [container[@"update_time"] isKindOfClass:NSNumber.class] ? container[@"update_time"] : nil;
        NSNumber *messageCreate = [message[@"create_time"] isKindOfClass:NSNumber.class] ? message[@"create_time"] : nil;
        NSNumber *finishTime = [metadata[@"finish_time"] isKindOfClass:NSNumber.class] ? metadata[@"finish_time"] : nil;
        serverAdvanced = CERecoveryTimestampNearOrAfter(rootUpdate, cutoff) || CERecoveryTimestampNearOrAfter(messageCreate, cutoff) || CERecoveryTimestampNearOrAfter(finishTime, cutoff);
    }
    NSString *summary = [NSString stringWithFormat:@"bytes=%lu rootID=%@ currentNode=%@ mapping=%lu messageID=%@ role=%@ status=%@ endTurn=%@ contentType=%@ parts=%lu textChars=%lu rootUpdate=%@ create=%@ finish=%@",
        (unsigned long)data.length,
        [container[@"id"] isKindOfClass:NSString.class] ? container[@"id"] : ([container[@"conversation_id"] isKindOfClass:NSString.class] ? container[@"conversation_id"] : @"<nil>"),
        currentNode ?: @"<nil>", (unsigned long)mapping.count,
        [message[@"id"] isKindOfClass:NSString.class] ? message[@"id"] : @"<nil>",
        [author[@"role"] isKindOfClass:NSString.class] ? author[@"role"] : @"<nil>",
        [message[@"status"] isKindOfClass:NSString.class] ? message[@"status"] : @"<nil>",
        endTurn ? endTurn.stringValue : @"<nil>",
        [content[@"content_type"] isKindOfClass:NSString.class] ? content[@"content_type"] : @"<nil>",
        (unsigned long)parts.count, (unsigned long)textChars,
        [container[@"update_time"] description] ?: @"<nil>", [message[@"create_time"] description] ?: @"<nil>", [metadata[@"finish_time"] description] ?: @"<nil>"];
    return @{ @"summary": summary, @"finished": @(finished), @"serverAdvanced": @(serverAdvanced) };
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
    if (!objc_getAssociatedObject(task, CERecoveryTaskFirstResumeDateKey)) objc_setAssociatedObject(task, CERecoveryTaskFirstResumeDateKey, NSDate.date, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @synchronized (CERecoveryTrackedStreamTasks) {
        [CERecoveryTrackedStreamTasks addObject:task];
        if (CERecoveryBackgroundDate && UIApplication.sharedApplication.applicationState != UIApplicationStateActive) CERecoveryHadStreamAtBackground = YES;
    }
    CERecoveryDiagnosticLog(@"STREAM", @"track task=%@ state=%@ method=%@ path=%@", NSStringFromClass(task.class), CERecoveryTaskStateName(task.state), request.HTTPMethod ?: @"<nil>", request.URL.path ?: @"<nil>");
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

static void CERecoveryCheckServer(NSString *conversationID, NSDate *cutoff, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    if (![[CEAPIClient shared] isReady]) {
        CERecoveryDiagnosticLog(@"AUTO-CHECK", @"attempt=%lu skipped apiReady=NO conversation=%@", (unsigned long)attempt, conversationID);
        if (attempt < 2) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((attempt ? 2.0 : 1.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, generation, attempt + 1); });
        return;
    }
    CERecoveryDiagnosticLog(@"AUTO-CHECK", @"attempt=%lu conversation=%@ trackedStreamRequired=YES", (unsigned long)attempt, conversationID);
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSInteger statusCode = response.statusCode; NSData *payload = [data copy]; NSString *errorText = [error.localizedDescription copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary *analysis = (!error && statusCode >= 200 && statusCode < 300) ? CERecoveryAnalyzeConversation(payload, cutoff) : @{ @"summary": [NSString stringWithFormat:@"bytes=%lu", (unsigned long)payload.length], @"finished": @NO, @"serverAdvanced": @NO };
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
                NSString *nowID = [CEConversationContext shared].conversationID; if (nowID.length && ![nowID isEqualToString:conversationID]) return;
                CERecoveryLastServerSummary = analysis[@"summary"];
                CERecoveryDiagnosticLog(@"AUTO-CHECK", @"response status=%ld error=%@ %@", (long)statusCode, errorText ?: @"<nil>", CERecoveryLastServerSummary ?: @"<nil>");
                BOOL finished = [analysis[@"finished"] boolValue]; BOOL serverAdvanced = [analysis[@"serverAdvanced"] boolValue];
                if (finished) {
                    CERecoveryCancelStreams(cutoff, YES, @"foreground-stale-stream", ^(NSUInteger cancelled) {
                        CERecoveryLastSafetyState = cancelled ? [NSString stringWithFormat:@"foreground cancelled %lu stale stream task(s); no navigation", (unsigned long)cancelled] : @"foreground server finished; no stale tracked stream remained";
                        CERecoveryDiagnosticLog(@"NAV-GUARD", @"foreground conversation=%@ serverAdvanced=%@ cancelled=%lu; route/history replay suppressed", conversationID, serverAdvanced ? @"YES" : @"NO", (unsigned long)cancelled);
                    });
                    return;
                }
                if (attempt < 2) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((attempt ? 3.0 : 1.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, generation, attempt + 1); });
            });
        });
    }];
}

@interface NSURLSessionTask (ChatGPTEnhancerForegroundRecovery)
- (void)ce_recovery_resume;
@end

@implementation NSURLSessionTask (ChatGPTEnhancerForegroundRecovery)
- (void)ce_recovery_resume {
    CERecoveryTrackStreamTask(self);
    [self ce_recovery_resume];
}
@end

void CEPullLatestConversationResult(NSString *conversationID) {
    CERecoveryDiagnosticMark(@"MANUAL PULL LATEST SAFE");
    CERecoveryDiagnosticLog(@"PULL", @"safe fetch start conversation=%@ appState=%ld apiReady=%@", conversationID ?: @"<nil>", (long)UIApplication.sharedApplication.applicationState, [[CEAPIClient shared] isReady] ? @"YES" : @"NO");
    if (!conversationID.length) { CEShowMessage(@"无法识别当前会话。"); return; }
    if (![[CEAPIClient shared] isReady]) { CEShowMessage(@"官方网络会话尚未就绪。"); return; }
    CEShowMessage(@"正在拉取最新消息…");
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    [[CEAPIClient shared] getPath:path progress:^(NSString *message) { if (message.length) CEShowMessage(message); } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSInteger statusCode = response.statusCode; NSData *payload = [data copy]; NSString *errorText = [error.localizedDescription copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary *analysis = (!error && statusCode >= 200 && statusCode < 300) ? CERecoveryAnalyzeConversation(payload, nil) : @{ @"summary": [NSString stringWithFormat:@"bytes=%lu", (unsigned long)payload.length], @"finished": @NO, @"serverAdvanced": @NO };
            dispatch_async(dispatch_get_main_queue(), ^{
                CERecoveryLastManualPullSummary = analysis[@"summary"];
                CERecoveryDiagnosticLog(@"PULL", @"GET complete status=%ld error=%@ %@", (long)statusCode, errorText ?: @"<nil>", CERecoveryLastManualPullSummary ?: @"<nil>");
                if (error || statusCode < 200 || statusCode >= 300 || !payload.length) { CEShowMessage(errorText.length ? errorText : @"拉取最新消息失败。"); return; }
                if (![analysis[@"finished"] boolValue]) { CEShowMessage(@"服务端仍在生成中。"); return; }
                CERecoveryCancelStreams(nil, NO, @"manual-pull-latest", ^(NSUInteger cancelled) {
                    CERecoveryLastSafetyState = cancelled ? [NSString stringWithFormat:@"manual pull cancelled %lu active stream task(s); no navigation", (unsigned long)cancelled] : @"manual pull fetched latest server result; no active stream; no navigation";
                    CERecoveryDiagnosticLog(@"NAV-GUARD", @"manual pull conversation=%@ cancelled=%lu; route/history replay suppressed", conversationID, (unsigned long)cancelled);
                    CEShowMessage(cancelled ? @"已拉取最新结果，已触发官方流恢复。" : @"已拉取服务端最新结果。");
                });
            });
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
            CERecoveryBackgroundDate = NSDate.date;
            CERecoveryConversationID = [[CEConversationContext shared].conversationID copy];
            CERecoveryHadStreamAtBackground = CERecoveryHasActiveTrackedStream();
            CERecoveryGeneration++;
            CERecoveryDiagnosticLog(@"LIFECYCLE", @"background conversation=%@ activeTrackedStream=%@ generation=%lu", CERecoveryConversationID ?: @"<nil>", CERecoveryHadStreamAtBackground ? @"YES" : @"NO", (unsigned long)CERecoveryGeneration);
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CERecoveryLastForegroundDate = NSDate.date;
            NSDate *cutoff = CERecoveryBackgroundDate; NSString *conversationID = [CERecoveryConversationID copy]; BOOL hadStreamAtBackground = CERecoveryHadStreamAtBackground;
            NSUInteger generation = ++CERecoveryGeneration;
            CERecoveryBackgroundDate = nil; CERecoveryConversationID = nil; CERecoveryHadStreamAtBackground = NO;
            NSTimeInterval backgroundAge = cutoff ? [NSDate.date timeIntervalSinceDate:cutoff] : 0;
            CERecoveryDiagnosticLog(@"LIFECYCLE", @"foreground priorConversation=%@ backgroundDuration=%.3f hadStream=%@ generation=%lu", conversationID ?: @"<nil>", backgroundAge, hadStreamAtBackground ? @"YES" : @"NO", (unsigned long)generation);
            if (!cutoff || !conversationID.length || backgroundAge < 1.0 || !hadStreamAtBackground) {
                CERecoveryLastSafetyState = @"passive foreground return; no tracked stream, server check skipped";
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, generation, 0); });
        }];
        CERecoveryDiagnosticLog(@"NAV-GUARD", @"lightweight foreground recovery installed; normal foreground returns do not fetch conversation data");
    });
}

NSString *CEForegroundStreamRecoveryDiagnosticsSnapshot(void) {
    NSUInteger tracked = 0, active = 0;
    @synchronized (CERecoveryTrackedStreamTasks) {
        tracked = CERecoveryTrackedStreamTasks.allObjects.count;
        for (NSURLSessionTask *task in CERecoveryTrackedStreamTasks.allObjects) if (task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended) active++;
    }
    return [NSString stringWithFormat:@"navigationRecoveryEnabled=NO\nforegroundCheckRequiresTrackedStream=YES\nautomaticHeavyProbeEnabled=NO\ngeneration=%lu\nbackgroundDate=%@\nbackgroundConversation=%@\nhadStreamAtBackground=%@\nlastForegroundDate=%@\ntrackedTasks=%lu activeTracked=%lu\nlastServerSummary=%@\nlastManualPullSummary=%@\nlastSafetyState=%@",
        (unsigned long)CERecoveryGeneration, CERecoveryBackgroundDate ?: (id)@"<nil>", CERecoveryConversationID ?: @"<nil>", CERecoveryHadStreamAtBackground ? @"YES" : @"NO", CERecoveryLastForegroundDate ?: (id)@"<nil>", (unsigned long)tracked, (unsigned long)active, CERecoveryLastServerSummary ?: @"<nil>", CERecoveryLastManualPullSummary ?: @"<nil>", CERecoveryLastSafetyState ?: @"<nil>"];
}

__attribute__((constructor)) static void CEForegroundStreamRecoveryEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ CERecoveryInstall(); });
    }
}
