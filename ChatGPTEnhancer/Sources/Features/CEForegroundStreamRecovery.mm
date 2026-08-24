#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
#import <objc/runtime.h>

extern BOOL CERefreshConversationFromHistory(NSString *conversationID);

static const void *CERecoveryTaskFirstResumeDateKey = &CERecoveryTaskFirstResumeDateKey;
static NSDate *CERecoveryBackgroundDate = nil;
static NSString *CERecoveryConversationID = nil;
static NSUInteger CERecoveryGeneration = 0;

static BOOL CERecoveryConversationFinished(NSData *data, NSDate *cutoff, BOOL *updatedNearBackground) {
    if (updatedNearBackground) *updatedNearBackground = NO;
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
    if (cutoff && updatedNearBackground) {
        NSTimeInterval threshold = cutoff.timeIntervalSince1970 - 5.0;
        NSNumber *rootUpdate = [root[@"update_time"] isKindOfClass:NSNumber.class] ? root[@"update_time"] : nil;
        NSNumber *messageCreate = [message[@"create_time"] isKindOfClass:NSNumber.class] ? message[@"create_time"] : nil;
        NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : nil;
        NSNumber *finishTime = [metadata[@"finish_time"] isKindOfClass:NSNumber.class] ? metadata[@"finish_time"] : nil;
        if ((rootUpdate && rootUpdate.doubleValue >= threshold) || (messageCreate && messageCreate.doubleValue >= threshold) || (finishTime && finishTime.doubleValue >= threshold)) *updatedNearBackground = YES;
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

static void CERecoveryRefreshConversation(NSString *conversationID, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (!currentID.length || ![currentID isEqualToString:conversationID]) return;
    if (CERefreshConversationFromHistory(conversationID)) {
        NSLog(@"[ChatGPTEnhancer] foreground recovery refreshed completed conversation %@", conversationID);
        return;
    }
    if (attempt >= 1) {
        NSLog(@"[ChatGPTEnhancer] foreground recovery could not refresh completed conversation %@", conversationID);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryRefreshConversation(conversationID, generation, attempt + 1); });
}

static void CERecoveryCancelStaleStreamTasks(NSDate *cutoff, NSString *conversationID, NSUInteger generation, BOOL serverAdvanced) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!cutoff || !conversationID.length) return;
    if (!session) {
        if (serverAdvanced) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryRefreshConversation(conversationID, generation, 0); });
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
            if (cancelled) NSLog(@"[ChatGPTEnhancer] foreground recovery found server-complete %@ and cancelled %lu stale task%@", conversationID, (unsigned long)cancelled, cancelled == 1 ? @"" : @"s");
            else NSLog(@"[ChatGPTEnhancer] foreground recovery server is complete for %@ with no stale stream task", conversationID);
            if (serverAdvanced || cancelled) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryRefreshConversation(conversationID, generation, 0); });
        });
    }];
}

static void CERecoveryCheckServer(NSString *conversationID, NSDate *cutoff, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    if (![[CEAPIClient shared] isReady]) {
        if (attempt < 3) {
            NSTimeInterval delay = attempt == 0 ? 0.8 : attempt == 1 ? 1.5 : 3.0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, generation, attempt + 1); });
        }
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", conversationID];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        BOOL serverAdvanced = NO;
        if (!error && response.statusCode >= 200 && response.statusCode < 300 && CERecoveryConversationFinished(data, cutoff, &serverAdvanced)) {
            CERecoveryCancelStaleStreamTasks(cutoff, conversationID, generation, serverAdvanced);
            return;
        }
        if (attempt < 3) {
            NSTimeInterval delay = attempt == 0 ? 1.0 : attempt == 1 ? 2.0 : 4.0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, generation, attempt + 1); });
        }
    }];
}

@interface NSURLSessionTask (ChatGPTEnhancerForegroundRecovery)
- (void)ce_recovery_resume;
@end

@implementation NSURLSessionTask (ChatGPTEnhancerForegroundRecovery)
- (void)ce_recovery_resume {
    if (!objc_getAssociatedObject(self, CERecoveryTaskFirstResumeDateKey)) objc_setAssociatedObject(self, CERecoveryTaskFirstResumeDateKey, NSDate.date, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self ce_recovery_resume];
}
@end

static void CERecoveryInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CESwizzleInstanceMethod(NSURLSessionTask.class, @selector(resume), @selector(ce_recovery_resume));
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CERecoveryBackgroundDate = NSDate.date;
            CERecoveryConversationID = [[CEConversationContext shared].conversationID copy];
            CERecoveryGeneration++;
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NSDate *cutoff = CERecoveryBackgroundDate;
            NSString *conversationID = [CERecoveryConversationID copy];
            NSUInteger generation = ++CERecoveryGeneration;
            CERecoveryBackgroundDate = nil;
            CERecoveryConversationID = nil;
            if (!cutoff || !conversationID.length || [NSDate.date timeIntervalSinceDate:cutoff] < 1.0) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, generation, 0); });
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
