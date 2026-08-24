#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
#import "../Storage/CECatalog.h"
#import "CEForegroundStreamRecovery.h"
#import "CEOrphanedConversationRecovery.h"
#import <objc/runtime.h>

static const void *CERecoveryTaskFirstResumeDateKey = &CERecoveryTaskFirstResumeDateKey;
static NSDate *CERecoveryBackgroundDate = nil;
static NSString *CERecoveryConversationID = nil;
static NSUInteger CERecoveryGeneration = 0;
static BOOL CERecoveryHadStreamAtBackground = NO;
static NSHashTable<NSURLSessionTask *> *CERecoveryTrackedStreamTasks = nil;

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
    if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    if (CEOrphanReselectConversation(conversationID)) {
        NSLog(@"[ChatGPTEnhancer] foreground recovery forced completed conversation reload for %@", conversationID);
        return;
    }
    if (attempt >= 1) {
        NSLog(@"[ChatGPTEnhancer] foreground recovery could not reselect completed conversation %@", conversationID);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryForceConversationReloadAttempt(conversationID, generation, attempt + 1); });
}

static void CERecoveryForceConversationReload(NSString *conversationID, NSUInteger generation, NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryForceConversationReloadAttempt(conversationID, generation, 0); });
}

static void CERecoveryCancelStaleStreamTasks(NSDate *cutoff, NSString *conversationID, NSUInteger generation, BOOL forceReload, void (^completion)(NSUInteger cancelled)) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!cutoff || !conversationID.length) { if (completion) completion(0); return; }
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
            [task cancel]; cancelled++;
            NSLog(@"[ChatGPTEnhancer] foreground recovery cancelled stale stream task %@ %@ started=%@", request.HTTPMethod ?: @"", request.URL.path ?: @"", firstResume);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            if (cancelled) NSLog(@"[ChatGPTEnhancer] foreground recovery triggered official stream recovery for %@ (%lu stale task%@)", conversationID, (unsigned long)cancelled, cancelled == 1 ? @"" : @"s");
            else NSLog(@"[ChatGPTEnhancer] foreground recovery server is complete for %@ but no stale stream task remained", conversationID);
            if (forceReload) CERecoveryForceConversationReload(conversationID, generation, cancelled ? 0.55 : 0.15);
            if (completion) completion(cancelled);
        });
    }];
}

static void CERecoveryCheckServer(NSString *conversationID, NSDate *cutoff, BOOL hadStreamAtBackground, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
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
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        BOOL serverAdvanced = NO;
        if (!error && response.statusCode >= 200 && response.statusCode < 300 && CERecoveryConversationFinished(data, cutoff, &serverAdvanced)) {
            BOOL forceReload = hadStreamAtBackground || serverAdvanced;
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
    if (!conversationID.length) { CEShowMessage(@"无法识别当前会话。"); return; }
    if (![[CEAPIClient shared] isReady]) { CEShowMessage(@"官方网络会话尚未就绪。"); return; }
    CEShowMessage(@"正在拉取最新消息…");
    NSString *encoded = [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", encoded];
    [[CEAPIClient shared] getPath:path progress:^(NSString *message) { if (message.length) CEShowMessage(message); } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || response.statusCode < 200 || response.statusCode >= 300 || !data.length) { CEShowMessage(error.localizedDescription.length ? error.localizedDescription : @"拉取最新消息失败。"); return; }
        NSString *origin = [CENetworkObserver shared].baseOrigin.length ? [CENetworkObserver shared].baseOrigin : @"https://ios.chat.openai.com";
        NSURL *requestURL = [NSURL URLWithString:[origin stringByAppendingString:path]];
        if (requestURL) [[CECatalog shared] ingestResponseData:data requestURL:requestURL];
        BOOL serverAdvanced = NO;
        if (!CERecoveryConversationFinished(data, nil, &serverAdvanced)) { CEShowMessage(@"服务端仍在生成中。"); return; }
        NSURLSession *session = [CENetworkObserver shared].requestSession;
        if (!session) { CEShowMessage(@"已拉取最新结果；当前无可恢复流，可使用“重载当前会话”。"); return; }
        [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
            __block NSUInteger cancelled = 0;
            for (NSURLSessionTask *task in tasks) {
                if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
                NSURLRequest *request = task.currentRequest ?: task.originalRequest;
                if (!CERecoveryLooksLikeConversationStream(request)) continue;
                [task cancel]; cancelled++;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (cancelled) CEShowMessage(@"已拉取最新结果，正在同步…");
                else CEShowMessage(@"已拉取最新结果；界面未更新时可重载当前会话。");
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
            CERecoveryBackgroundDate = NSDate.date;
            CERecoveryConversationID = [[CEConversationContext shared].conversationID copy];
            CERecoveryHadStreamAtBackground = CERecoveryHasActiveTrackedStream();
            CERecoveryGeneration++;
            NSLog(@"[ChatGPTEnhancer] foreground recovery background snapshot conversation=%@ activeStream=%@", CERecoveryConversationID ?: @"<nil>", CERecoveryHadStreamAtBackground ? @"YES" : @"NO");
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NSDate *cutoff = CERecoveryBackgroundDate;
            NSString *conversationID = [CERecoveryConversationID copy];
            BOOL hadStreamAtBackground = CERecoveryHadStreamAtBackground;
            NSUInteger generation = ++CERecoveryGeneration;
            CERecoveryBackgroundDate = nil;
            CERecoveryConversationID = nil;
            CERecoveryHadStreamAtBackground = NO;
            if (!cutoff || !conversationID.length || [NSDate.date timeIntervalSinceDate:cutoff] < 1.0) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, 0); });
        }];
        NSLog(@"[ChatGPTEnhancer] foreground stream recovery installed");
    });
}

__attribute__((constructor)) static void CEForegroundStreamRecoveryEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryInstall(); });
    }
}
