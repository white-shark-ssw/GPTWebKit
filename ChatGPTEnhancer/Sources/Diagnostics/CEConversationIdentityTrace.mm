#import "CEConversationIdentityTrace.h"
#import "../Core/CECore.h"
#import <UIKit/UIKit.h>

static NSString * const CETraceActiveKey = @"ChatGPTEnhancer.IdentityTrace.Active";
static NSString * const CETraceSessionKey = @"ChatGPTEnhancer.IdentityTrace.SessionID";
static NSString *CETraceLaunchID = nil;
static NSUInteger CETraceSequence = 0;
static __thread BOOL CENavigationTraceReentrant = NO;
static void CEInstallNavigationTraceHooks(void);

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
        CETraceLaunchID = NSUUID.UUID.UUIDString; CEInstallNavigationTraceHooks();
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

static BOOL CETraceIsExactConversationDetailPath(NSString *path, NSString *conversationID) {
    if (!path.length || !conversationID.length) return NO;
    NSString *cid = conversationID.lowercaseString;
    return [path isEqualToString:[NSString stringWithFormat:@"/backend-api/conversation/%@", cid]] || [path isEqualToString:[NSString stringWithFormat:@"/backend-api/f/conversation/%@", cid]];
}

static NSString *CETraceRefreshStage(NSURLRequest *request, NSArray<NSString *> *urlIDs, NSArray<NSString *> *bodyIDs) {
    NSString *path = request.URL.path.lowercaseString ?: @""; NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/backend-api/conversation/init"]) return bodyIDs.count == 1 ? @"exact-init" : (bodyIDs.count == 0 ? @"staging-init" : nil);
    if ([method isEqualToString:@"POST"] && ([path isEqualToString:@"/backend-api/f/conversation/prepare"] || [path isEqualToString:@"/backend-api/conversation/prepare"])) return bodyIDs.count == 1 ? @"exact-prepare" : (bodyIDs.count == 0 ? @"staging-prepare" : nil);
    if ([method isEqualToString:@"GET"] && urlIDs.count == 1 && CETraceIsExactConversationDetailPath(path, urlIDs.firstObject)) return @"detail";
    return nil;
}

static NSString *CETraceCompactStack(NSUInteger limit) {
    NSMutableArray<NSString *> *frames = [NSMutableArray array];
    for (NSString *raw in NSThread.callStackSymbols ?: @[]) {
        if ([raw containsString:@"ChatGPTEnhancer"] || [raw containsString:@"CEConversationIdentityTrace"] || [raw containsString:@"CENetworkObserver"]) continue;
        NSString *frame = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!frame.length) continue;
        static NSRegularExpression *addressRE; static dispatch_once_t once;
        dispatch_once(&once, ^{ addressRE = [NSRegularExpression regularExpressionWithPattern:@"0x[0-9a-fA-F]+" options:0 error:nil]; });
        frame = [addressRE stringByReplacingMatchesInString:frame options:0 range:NSMakeRange(0, frame.length) withTemplate:@"0x…"];
        if (frame.length > 220) frame = [[frame substringToIndex:220] stringByAppendingString:@"…"];
        [frames addObject:frame]; if (frames.count >= limit) break;
    }
    return frames.count ? [frames componentsJoinedByString:@" || "] : @"<none>";
}

static UINavigationController *CETraceNavigationController(UIViewController *top) {
    if ([top isKindOfClass:UINavigationController.class]) return (UINavigationController *)top;
    return top.navigationController;
}

static NSString *CETraceNavigationStackFromControllers(NSArray<UIViewController *> *controllers) {
    NSMutableArray<NSString *> *classes = [NSMutableArray array];
    for (UIViewController *controller in controllers ?: @[]) {
        [classes addObject:NSStringFromClass(controller.class) ?: @"<unknown>"];
        if (classes.count >= 8) break;
    }
    return classes.count ? [classes componentsJoinedByString:@">"] : @"<empty>";
}

static NSString *CETraceNavigationStack(UINavigationController *nav) { return nav ? CETraceNavigationStackFromControllers(nav.viewControllers) : @"<none>"; }

static void CETraceNavigationMutation(UINavigationController *nav, NSString *source, NSArray<UIViewController *> *before, NSString *beforeVisible, BOOL animated, NSString *caller) {
    if (!CEConversationIdentityTraceIsRecording() || !nav || !source.length) return;
    NSArray<UIViewController *> *after = [nav.viewControllers copy] ?: @[]; NSString *beforeStack = CETraceNavigationStackFromControllers(before); NSString *afterStack = CETraceNavigationStackFromControllers(after);
    if (before.count == after.count && [beforeStack isEqualToString:afterStack]) return;
    CEConversationContext *context = [CEConversationContext shared];
    CETraceAppend(@"NAV-MUTATION", [NSString stringWithFormat:@"source=%@ animated=%@ main=%@ nav=%@ contextID=%@ beforeCount=%lu beforeStack=%@ beforeVisible=%@ afterCount=%lu afterStack=%@ afterVisible=%@ caller=%@",
        source, animated ? @"YES" : @"NO", NSThread.isMainThread ? @"YES" : @"NO", NSStringFromClass(nav.class) ?: @"<none>", context.conversationID ?: @"<none>",
        (unsigned long)before.count, beforeStack, beforeVisible ?: @"<none>", (unsigned long)after.count, afterStack, nav.visibleViewController ? NSStringFromClass(nav.visibleViewController.class) : @"<none>", caller ?: @"<none>"]);
}

@interface UINavigationController (ChatGPTEnhancerNavigationTrace)
- (void)ce_trace_setViewControllers:(NSArray<UIViewController *> *)viewControllers;
- (void)ce_trace_setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated;
- (void)ce_trace_pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (UIViewController *)ce_trace_popViewControllerAnimated:(BOOL)animated;
- (NSArray<UIViewController *> *)ce_trace_popToViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (NSArray<UIViewController *> *)ce_trace_popToRootViewControllerAnimated:(BOOL)animated;
@end

@implementation UINavigationController (ChatGPTEnhancerNavigationTrace)
- (void)ce_trace_setViewControllers:(NSArray<UIViewController *> *)viewControllers {
    if (!CEConversationIdentityTraceIsRecording() || CENavigationTraceReentrant) { [self ce_trace_setViewControllers:viewControllers]; return; }
    CENavigationTraceReentrant = YES; NSArray *before = [self.viewControllers copy] ?: @[]; NSString *beforeVisible = self.visibleViewController ? NSStringFromClass(self.visibleViewController.class) : nil; NSString *caller = CETraceCompactStack(12); [self ce_trace_setViewControllers:viewControllers]; CENavigationTraceReentrant = NO;
    CETraceNavigationMutation(self, @"setViewControllers:", before, beforeVisible, NO, caller);
}
- (void)ce_trace_setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    if (!CEConversationIdentityTraceIsRecording() || CENavigationTraceReentrant) { [self ce_trace_setViewControllers:viewControllers animated:animated]; return; }
    CENavigationTraceReentrant = YES; NSArray *before = [self.viewControllers copy] ?: @[]; NSString *beforeVisible = self.visibleViewController ? NSStringFromClass(self.visibleViewController.class) : nil; NSString *caller = CETraceCompactStack(12); [self ce_trace_setViewControllers:viewControllers animated:animated]; CENavigationTraceReentrant = NO;
    CETraceNavigationMutation(self, @"setViewControllers:animated:", before, beforeVisible, animated, caller);
}
- (void)ce_trace_pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (!CEConversationIdentityTraceIsRecording() || CENavigationTraceReentrant) { [self ce_trace_pushViewController:viewController animated:animated]; return; }
    CENavigationTraceReentrant = YES; NSArray *before = [self.viewControllers copy] ?: @[]; NSString *beforeVisible = self.visibleViewController ? NSStringFromClass(self.visibleViewController.class) : nil; NSString *caller = CETraceCompactStack(12); [self ce_trace_pushViewController:viewController animated:animated]; CENavigationTraceReentrant = NO;
    CETraceNavigationMutation(self, @"pushViewController:animated:", before, beforeVisible, animated, caller);
}
- (UIViewController *)ce_trace_popViewControllerAnimated:(BOOL)animated {
    if (!CEConversationIdentityTraceIsRecording() || CENavigationTraceReentrant) return [self ce_trace_popViewControllerAnimated:animated];
    CENavigationTraceReentrant = YES; NSArray *before = [self.viewControllers copy] ?: @[]; NSString *beforeVisible = self.visibleViewController ? NSStringFromClass(self.visibleViewController.class) : nil; NSString *caller = CETraceCompactStack(12); UIViewController *result = [self ce_trace_popViewControllerAnimated:animated]; CENavigationTraceReentrant = NO;
    CETraceNavigationMutation(self, @"popViewControllerAnimated:", before, beforeVisible, animated, caller); return result;
}
- (NSArray<UIViewController *> *)ce_trace_popToViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (!CEConversationIdentityTraceIsRecording() || CENavigationTraceReentrant) return [self ce_trace_popToViewController:viewController animated:animated];
    CENavigationTraceReentrant = YES; NSArray *before = [self.viewControllers copy] ?: @[]; NSString *beforeVisible = self.visibleViewController ? NSStringFromClass(self.visibleViewController.class) : nil; NSString *caller = CETraceCompactStack(12); NSArray<UIViewController *> *result = [self ce_trace_popToViewController:viewController animated:animated]; CENavigationTraceReentrant = NO;
    CETraceNavigationMutation(self, @"popToViewController:animated:", before, beforeVisible, animated, caller); return result;
}
- (NSArray<UIViewController *> *)ce_trace_popToRootViewControllerAnimated:(BOOL)animated {
    if (!CEConversationIdentityTraceIsRecording() || CENavigationTraceReentrant) return [self ce_trace_popToRootViewControllerAnimated:animated];
    CENavigationTraceReentrant = YES; NSArray *before = [self.viewControllers copy] ?: @[]; NSString *beforeVisible = self.visibleViewController ? NSStringFromClass(self.visibleViewController.class) : nil; NSString *caller = CETraceCompactStack(12); NSArray<UIViewController *> *result = [self ce_trace_popToRootViewControllerAnimated:animated]; CENavigationTraceReentrant = NO;
    CETraceNavigationMutation(self, @"popToRootViewControllerAnimated:", before, beforeVisible, animated, caller); return result;
}
@end

static void CEInstallNavigationTraceHooks(void) {
    CESwizzleInstanceMethod(UINavigationController.class, @selector(setViewControllers:), @selector(ce_trace_setViewControllers:));
    CESwizzleInstanceMethod(UINavigationController.class, @selector(setViewControllers:animated:), @selector(ce_trace_setViewControllers:animated:));
    CESwizzleInstanceMethod(UINavigationController.class, @selector(pushViewController:animated:), @selector(ce_trace_pushViewController:animated:));
    CESwizzleInstanceMethod(UINavigationController.class, @selector(popViewControllerAnimated:), @selector(ce_trace_popViewControllerAnimated:));
    CESwizzleInstanceMethod(UINavigationController.class, @selector(popToViewController:animated:), @selector(ce_trace_popToViewController:animated:));
    CESwizzleInstanceMethod(UINavigationController.class, @selector(popToRootViewControllerAnimated:), @selector(ce_trace_popToRootViewControllerAnimated:));
}

static void CETraceRefreshPathContext(NSURLRequest *request, NSArray<NSString *> *urlIDs, NSArray<NSString *> *bodyIDs) {
    NSString *stage = CETraceRefreshStage(request, urlIDs, bodyIDs); if (!stage.length) return;
    UIViewController *top = CETopViewController(); UINavigationController *nav = CETraceNavigationController(top); UIWindow *key = CEKeyWindow(); UIViewController *root = key.rootViewController;
    NSString *targetID = bodyIDs.firstObject ?: urlIDs.firstObject ?: @"<none>";
    CETraceAppend(@"REFRESH-PATH", [NSString stringWithFormat:@"stage=%@ method=%@ path=%@ target=%@ keyWindow=%@ rootVC=%@ topVC=%@ presentedVC=%@ nav=%@ navCount=%lu navStack=%@ navVisible=%@ stack=%@",
        stage, request.HTTPMethod ?: @"GET", request.URL.path ?: @"/", targetID,
        key ? NSStringFromClass(key.class) : @"<none>", root ? NSStringFromClass(root.class) : @"<none>", top ? NSStringFromClass(top.class) : @"<none>", top.presentedViewController ? NSStringFromClass(top.presentedViewController.class) : @"<none>",
        nav ? NSStringFromClass(nav.class) : @"<none>", (unsigned long)nav.viewControllers.count, CETraceNavigationStack(nav), nav.visibleViewController ? NSStringFromClass(nav.visibleViewController.class) : @"<none>", CETraceCompactStack(8)]);
}

void CEConversationIdentityTraceLogTaskCreation(NSURLRequest *request, NSString *source) {
    if (!CEConversationIdentityTraceIsRecording() || !request.URL || !source.length) return;
    NSArray<NSString *> *urlIDs = CETraceConversationIDsFromURL(request.URL); NSArray<NSString *> *bodyIDs = CETraceConversationIDsFromBody(request.HTTPBody);
    NSString *stage = CETraceRefreshStage(request, urlIDs, bodyIDs); if (!stage.length) return;
    UIViewController *top = CETopViewController(); UINavigationController *nav = CETraceNavigationController(top); UIWindow *key = CEKeyWindow(); UIViewController *root = key.rootViewController;
    NSString *targetID = bodyIDs.firstObject ?: urlIDs.firstObject ?: @"<none>";
    CETraceAppend(@"REFRESH-CREATE", [NSString stringWithFormat:@"source=%@ stage=%@ method=%@ path=%@ target=%@ keyWindow=%@ rootVC=%@ topVC=%@ presentedVC=%@ nav=%@ navCount=%lu navStack=%@ navVisible=%@ caller=%@",
        source, stage, request.HTTPMethod ?: @"GET", request.URL.path ?: @"/", targetID,
        key ? NSStringFromClass(key.class) : @"<none>", root ? NSStringFromClass(root.class) : @"<none>", top ? NSStringFromClass(top.class) : @"<none>", top.presentedViewController ? NSStringFromClass(top.presentedViewController.class) : @"<none>",
        nav ? NSStringFromClass(nav.class) : @"<none>", (unsigned long)nav.viewControllers.count, CETraceNavigationStack(nav), nav.visibleViewController ? NSStringFromClass(nav.visibleViewController.class) : @"<none>", CETraceCompactStack(12)]);
}

void CEConversationIdentityTraceLogRequest(NSURLRequest *request) {
    if (!CEConversationIdentityTraceIsRecording() || !request.URL) return;
    NSArray<NSString *> *urlIDs = CETraceConversationIDsFromURL(request.URL); NSArray<NSString *> *bodyIDs = CETraceConversationIDsFromBody(request.HTTPBody); NSArray<NSString *> *queryNames = CETraceQueryNames(request.URL);
    NSString *path = request.URL.path ?: @"/"; BOOL share = [path.lowercaseString containsString:@"share"];
    CETraceAppend(share ? @"NET-SHARE-REQ" : @"NET-REQ", [NSString stringWithFormat:@"method=%@ path=%@ queryNames=%@ urlConversationIDs=%@ bodyConversationIDs=%@", request.HTTPMethod ?: @"GET", path, queryNames.count ? [queryNames componentsJoinedByString:@","] : @"<none>", urlIDs.count ? [urlIDs componentsJoinedByString:@","] : @"<none>", bodyIDs.count ? [bodyIDs componentsJoinedByString:@","] : @"<none>"]);
    CETraceRefreshPathContext(request, urlIDs, bodyIDs);
}

void CEConversationIdentityTraceLogResponse(NSURLRequest *request, NSURLResponse *response, NSError *error) {
    if (!CEConversationIdentityTraceIsRecording() || !request.URL) return;
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil; NSString *path = request.URL.path ?: @"/"; BOOL share = [path.lowercaseString containsString:@"share"];
    CETraceAppend(share ? @"NET-SHARE-RESP" : @"NET-RESP", [NSString stringWithFormat:@"method=%@ path=%@ status=%ld error=%@", request.HTTPMethod ?: @"GET", path, (long)http.statusCode, error ? [NSString stringWithFormat:@"%@/%ld", error.domain ?: @"error", (long)error.code] : @"<none>"]);
}
