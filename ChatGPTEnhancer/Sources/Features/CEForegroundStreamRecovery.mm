#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
#import "CEOrphanedConversationRecovery.h"
#import <objc/runtime.h>

static const void *CERecoveryTaskFirstResumeDateKey = &CERecoveryTaskFirstResumeDateKey;
static NSDate *CERecoveryBackgroundDate = nil;
static NSString *CERecoveryConversationID = nil;
static NSUInteger CERecoveryGeneration = 0;
static BOOL CERecoveryHadStreamAtBackground = NO;
static NSHashTable<NSURLSessionTask *> *CERecoveryTrackedStreamTasks = nil;

static BOOL CERecoveryConversationFinished(NSData *data) {
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
    if (![role isEqualToString:@"assistant"]) return NO;
    if (endTurn.boolValue) return YES;
    return [status containsString:@"finished"] || [status containsString:@"complete"] || [status containsString:@"success"] || [status isEqualToString:@"done"];
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

static void CERecoveryForceConversationReload(NSString *conversationID, NSUInteger generation, NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        NSString *currentID = [CEConversationContext shared].conversationID;
        if (currentID.length && ![currentID isEqualToString:conversationID]) return;
        if (CEOrphanReselectConversation(conversationID)) NSLog(@"[ChatGPTEnhancer] foreground recovery forced completed conversation reload for %@", conversationID);
        else NSLog(@"[ChatGPTEnhancer] foreground recovery could not reselect completed conversation %@", conversationID);
    });
}

static void CERecoveryCancelStaleStreamTasks(NSDate *cutoff, NSString *conversationID, NSUInteger generation, BOOL forceReload, void (^completion)(NSUInteger cancelled)) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!session || !cutoff || !conversationID.length) { if (completion) completion(0); return; }
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
            if (forceReload) CERecoveryForceConversationReload(conversationID, generation, cancelled ? 1.0 : 0.15);
            if (completion) completion(cancelled);
        });
    }];
}

static void CERecoveryCheckServer(NSString *conversationID, NSDate *cutoff, BOOL hadStreamAtBackground, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (currentID.length && ![currentID isEqualToString:conversationID]) return;
    if (![[CEAPIClient shared] isReady]) {
        if (attempt < 2) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, attempt + 1); });
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", conversationID];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (generation != CERecoveryGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        if (!error && response.statusCode >= 200 && response.statusCode < 300 && CERecoveryConversationFinished(data)) {
            CERecoveryCancelStaleStreamTasks(cutoff, conversationID, generation, hadStreamAtBackground, nil);
            return;
        }
        if (attempt < 2) {
            NSTimeInterval delay = attempt == 0 ? 2.0 : 4.0;
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CERecoveryCheckServer(conversationID, cutoff, hadStreamAtBackground, generation, 0); });
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
