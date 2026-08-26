#import "CEConversationIdentityTrace.h"
#import "../Core/CECore.h"
#import <UIKit/UIKit.h>

static NSString * const CETraceActiveKey = @"ChatGPTEnhancer.IdentityTrace.Active";
static NSString * const CETraceSessionKey = @"ChatGPTEnhancer.IdentityTrace.SessionID";
static NSString *CETraceLaunchID = nil;
static NSUInteger CETraceSequence = 0;

static NSObject *CETraceLock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static NSString *CETraceAppStateName(void) {
    switch (UIApplication.sharedApplication.applicationState) {
        case UIApplicationStateActive: return @"active";
        case UIApplicationStateInactive: return @"inactive";
        case UIApplicationStateBackground: return @"background";
    }
    return @"unknown";
}

static NSURL *CETraceDirectoryURL(void) {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if (!base) return nil;
    NSURL *directory = [[base URLByAppendingPathComponent:@"ChatGPTEnhancer" isDirectory:YES] URLByAppendingPathComponent:@"IdentityTrace" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static NSString *CETraceSessionID(void) { return [[NSUserDefaults standardUserDefaults] stringForKey:CETraceSessionKey]; }

static NSURL *CETraceFileURL(void) {
    NSString *sessionID = CETraceSessionID(); NSURL *directory = CETraceDirectoryURL();
    if (!sessionID.length || !directory) return nil;
    return [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"conversation-identity-%@.log", sessionID] isDirectory:NO];
}

static void CETraceEnsureFile(void) {
    NSURL *url = CETraceFileURL(); if (!url) return;
    if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    [@"ChatGPTEnhancer Conversation Identity Trace\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void CETraceAppend(NSString *category, NSString *message) {
    if (!CEConversationIdentityTraceIsRecording() || !message.length) return;
    CETraceEnsureFile(); NSURL *url = CETraceFileURL(); if (!url) return;
    NSString *flat = [[message stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    long long timestamp = (long long)(NSDate.date.timeIntervalSince1970 * 1000.0);
    @synchronized (CETraceLock()) {
        NSUInteger sequence = ++CETraceSequence;
        NSString *line = [NSString stringWithFormat:@"%06lu %lld launch=%@ %@ | %@\n", (unsigned long)sequence, timestamp, CETraceLaunchID ?: @"<none>", category.length ? category : @"TRACE", flat];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:url.path];
        if (!handle) return;
        @try { [handle seekToEndOfFile]; [handle writeData:data]; } @catch (__unused NSException *exception) {} [handle closeFile];
    }
}

BOOL CEConversationIdentityTraceIsRecording(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:CETraceActiveKey]; }

void CEConversationIdentityTraceLog(NSString *category, NSString *format, ...) {
    if (!CEConversationIdentityTraceIsRecording() || !format.length) return;
    va_list args; va_start(args, format); NSString *message = [[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    CETraceAppend(category, message);
}

void CEConversationIdentityTraceBegin(void) {
    if (CEConversationIdentityTraceIsRecording()) return;
    if (!CETraceLaunchID.length) CETraceLaunchID = NSUUID.UUID.UUIDString;
    NSString *sessionID = NSUUID.UUID.UUIDString;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; [defaults setObject:sessionID forKey:CETraceSessionKey]; [defaults setBool:YES forKey:CETraceActiveKey]; [defaults synchronize];
    NSURL *url = CETraceFileURL(); if (url) [@"ChatGPTEnhancer Conversation Identity Trace\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CETraceAppend(@"TRACE", [NSString stringWithFormat:@"BEGIN session=%@ enhancer=%@ app=%@ state=%@", sessionID, CEVersion, [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown", CETraceAppStateName()]);
}

NSURL *CEConversationIdentityTraceFinish(void) {
    if (!CEConversationIdentityTraceIsRecording()) return CETraceFileURL();
    CETraceAppend(@"TRACE", [NSString stringWithFormat:@"END session=%@ state=%@", CETraceSessionID() ?: @"<none>", CETraceAppStateName()]);
    NSURL *url = CETraceFileURL(); NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; [defaults setBool:NO forKey:CETraceActiveKey]; [defaults synchronize]; return url;
}

static void CETraceLifecycle(NSString *name) { CEConversationIdentityTraceLog(@"LIFECYCLE", @"%@ state=%@", name, CETraceAppStateName()); }

void CEConversationIdentityTraceStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CETraceLaunchID = NSUUID.UUID.UUIDString;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CETraceLifecycle(@"didBecomeActive"); }];
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CETraceLifecycle(@"willResignActive"); }];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CETraceLifecycle(@"didEnterBackground"); }];
        [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CETraceLifecycle(@"willEnterForeground"); }];
        [center addObserverForName:UIApplicationWillTerminateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CETraceLifecycle(@"willTerminate"); }];
        if (CEConversationIdentityTraceIsRecording()) CETraceAppend(@"TRACE", [NSString stringWithFormat:@"PROCESS-RESUME session=%@ enhancer=%@ app=%@ state=%@", CETraceSessionID() ?: @"<none>", CEVersion, [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown", CETraceAppStateName()]);
    });
}

static void CETraceCollectBodyConversationIDs(id value, NSMutableOrderedSet<NSString *> *out, NSUInteger depth) {
    if (!value || depth > 8) return;
    if ([value isKindOfClass:NSArray.class]) { for (id child in value) CETraceCollectBodyConversationIDs(child, out, depth + 1); return; }
    if (![value isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dictionary = value;
    for (id rawKey in dictionary) {
        NSString *key = [rawKey isKindOfClass:NSString.class] ? [(NSString *)rawKey lowercaseString] : @""; id child = dictionary[rawKey];
        if (([key isEqualToString:@"conversation_id"] || [key isEqualToString:@"conversationid"]) && [child isKindOfClass:NSString.class]) {
            NSString *cid = CEExtractConversationIDFromString(child); if (cid.length) [out addObject:cid];
        }
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) CETraceCollectBodyConversationIDs(child, out, depth + 1);
    }
}

static NSArray<NSString *> *CETraceConversationIDsFromBody(NSData *body) {
    if (!body.length) return @[];
    NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet]; id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (json) CETraceCollectBodyConversationIDs(json, out, 0);
    if (!out.count && body.length <= 128 * 1024) {
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        if (text.length) {
            static NSRegularExpression *re; static dispatch_once_t once;
            dispatch_once(&once, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"(?i)(?:conversation_id|conversationId)[\\\"'\\s:=]+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})" options:0 error:nil]; });
            for (NSTextCheckingResult *match in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) if (match.numberOfRanges > 1) [out addObject:[text substringWithRange:[match rangeAtIndex:1]]];
        }
    }
    return out.array;
}

static NSArray<NSString *> *CETraceQueryNames(NSURL *url) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO]; NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) if (item.name.length && item.name.length <= 80) [names addObject:item.name]; return names.array;
}

static NSArray<NSString *> *CETraceConversationIDsFromURL(NSURL *url) {
    if (!url) return @[]; NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet]; NSString *path = url.path.lowercaseString ?: @"";
    if ([path containsString:@"conversation"]) { NSString *cid = CEExtractConversationIDFromString(url.absoluteString ?: @""); if (cid.length) [out addObject:cid]; }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *name = item.name.lowercaseString; if (![name isEqualToString:@"conversation_id"] && ![name isEqualToString:@"conversationid"]) continue;
        NSString *cid = CEExtractConversationIDFromString(item.value ?: @""); if (cid.length) [out addObject:cid];
    }
    return out.array;
}

void CEConversationIdentityTraceLogRequest(NSURLRequest *request) {
    if (!CEConversationIdentityTraceIsRecording() || !request.URL) return;
    NSArray<NSString *> *urlIDs = CETraceConversationIDsFromURL(request.URL); NSArray<NSString *> *bodyIDs = CETraceConversationIDsFromBody(request.HTTPBody); NSArray<NSString *> *queryNames = CETraceQueryNames(request.URL);
    NSString *path = request.URL.path ?: @"/"; BOOL share = [path.lowercaseString containsString:@"share"];
    CETraceAppend(share ? @"NET-SHARE-REQ" : @"NET-REQ", [NSString stringWithFormat:@"method=%@ path=%@ queryNames=%@ urlConversationIDs=%@ bodyConversationIDs=%@", request.HTTPMethod ?: @"GET", path, queryNames.count ? [queryNames componentsJoinedByString:@","] : @"<none>", urlIDs.count ? [urlIDs componentsJoinedByString:@","] : @"<none>", bodyIDs.count ? [bodyIDs componentsJoinedByString:@","] : @"<none>"]);
}

void CEConversationIdentityTraceLogResponse(NSURLRequest *request, NSURLResponse *response, NSError *error) {
    if (!CEConversationIdentityTraceIsRecording() || !request.URL) return;
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil; NSString *path = request.URL.path ?: @"/"; BOOL share = [path.lowercaseString containsString:@"share"];
    CETraceAppend(share ? @"NET-SHARE-RESP" : @"NET-RESP", [NSString stringWithFormat:@"method=%@ path=%@ status=%ld error=%@", request.HTTPMethod ?: @"GET", path, (long)http.statusCode, error ? [NSString stringWithFormat:@"%@/%ld", error.domain ?: @"error", (long)error.code] : @"<none>"]);
}
