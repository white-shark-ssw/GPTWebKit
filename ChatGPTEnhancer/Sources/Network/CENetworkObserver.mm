#import "CENetworkObserver.h"
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Diagnostics/CEConversationIdentityTrace.h"
#import <objc/runtime.h>

static NSString * const CEInternalHeader = @"X-ChatGPTEnhancer-Internal";
static const void *CEInternalTaskKey = &CEInternalTaskKey;
static const void *CESessionTaskKey = &CESessionTaskKey;
static const void *CEResponseBufferKey = &CEResponseBufferKey;
static const void *CEDelegateHookedKey = &CEDelegateHookedKey;
static const void *CETraceNetworkTokenKey = &CETraceNetworkTokenKey;
static NSUInteger CETraceNetworkTokenSequence = 0;

static void CEMarkInternalTask(NSURLSessionTask *task) { if (task) objc_setAssociatedObject(task, CEInternalTaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL CEIsInternalTask(NSURLSessionTask *task) { return [objc_getAssociatedObject(task, CEInternalTaskKey) boolValue]; }
static void CEAssociateSession(NSURLSessionTask *task, NSURLSession *session) { if (task && session) objc_setAssociatedObject(task, CESessionTaskKey, session, OBJC_ASSOCIATION_ASSIGN); }
static NSURLSession *CESessionForTask(NSURLSessionTask *task) { return task ? objc_getAssociatedObject(task, CESessionTaskKey) : nil; }

static NSString *CETraceNetworkToken(id object, NSString *prefix) {
    if (!object || !CEConversationIdentityTraceIsRecording()) return @"<none>";
    NSString *token = objc_getAssociatedObject(object, CETraceNetworkTokenKey); if (token.length) return token;
    @synchronized (CENetworkObserver.class) {
        token = objc_getAssociatedObject(object, CETraceNetworkTokenKey);
        if (!token.length) { token = [NSString stringWithFormat:@"%@-%lu", prefix ?: @"net", (unsigned long)++CETraceNetworkTokenSequence]; objc_setAssociatedObject(object, CETraceNetworkTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    }
    return token;
}

static BOOL CERequestHasAuth(NSURLRequest *request) {
    for (NSString *key in request.allHTTPHeaderFields ?: @{}) {
        NSString *lower = key.lowercaseString;
        if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"chatgpt-account-id"] || [lower isEqualToString:@"cookie"] || [lower isEqualToString:@"oai-app-sid"]) return YES;
    }
    return NO;
}

static void CECollectExplicitConversationIDs(id value, NSMutableOrderedSet<NSString *> *out, NSUInteger depth) {
    if (!value || depth > 8) return;
    if ([value isKindOfClass:NSArray.class]) { for (id child in value) CECollectExplicitConversationIDs(child, out, depth + 1); return; }
    if (![value isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dictionary = value;
    for (id rawKey in dictionary) {
        NSString *key = [rawKey isKindOfClass:NSString.class] ? [(NSString *)rawKey lowercaseString] : @""; id child = dictionary[rawKey];
        if (([key isEqualToString:@"conversation_id"] || [key isEqualToString:@"conversationid"]) && [child isKindOfClass:NSString.class]) {
            NSString *cid = CEExtractConversationIDFromString(child); if (cid.length) [out addObject:cid];
        }
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) CECollectExplicitConversationIDs(child, out, depth + 1);
    }
}

static NSString *CEExplicitConversationInitID(NSURLRequest *request) {
    if (!request.URL || ![request.HTTPMethod.uppercaseString isEqualToString:@"POST"] || ![request.URL.path.lowercaseString isEqualToString:@"/backend-api/conversation/init"] || !request.HTTPBody.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil]; if (!json) return nil;
    NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet]; CECollectExplicitConversationIDs(json, ids, 0);
    return ids.count == 1 ? ids.firstObject : nil;
}

static void CEApplyExplicitConversationInitIdentity(NSURLRequest *request) {
    NSString *conversationID = CEExplicitConversationInitID(request); if (!conversationID.length) return;
    CEConversationRecord *record = [[CECatalog shared] recordForID:conversationID];
    [[CEConversationContext shared] setConversationID:conversationID title:record.title];
    CEConversationIdentityTraceLog(@"IDENTITY-INIT", @"accepted exact conversation/init id=%@ title=%@", conversationID, record.title ?: @"<none>");
}

static NSArray<NSString *> *CETraceSortedJSONKeys(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return @[];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (id rawKey in [(NSDictionary *)value allKeys]) if ([rawKey isKindOfClass:NSString.class] && [(NSString *)rawKey length] <= 80) [keys addObject:rawKey];
    [keys sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if (keys.count > 32) [keys removeObjectsInRange:NSMakeRange(32, keys.count - 32)];
    return keys;
}

static NSString *CETraceRequestBodyKeys(NSURLRequest *request) {
    if (!request.HTTPBody.length) return @"<none>";
    id json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
    NSArray<NSString *> *keys = CETraceSortedJSONKeys(json);
    return keys.count ? [keys componentsJoinedByString:@","] : @"<non-dictionary-or-non-json>";
}

static NSString *CETraceConversationStage(NSURLRequest *request, NSString **conversationIDOut) {
    if (!request.URL) return nil;
    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET"; NSString *path = request.URL.path.lowercaseString ?: @"";
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/backend-api/conversation/init"]) {
        NSString *cid = CEExplicitConversationInitID(request); if (conversationIDOut) *conversationIDOut = cid; return cid.length ? @"exact-init" : @"staging-init";
    }
    if ([method isEqualToString:@"POST"] && ([path isEqualToString:@"/backend-api/f/conversation/prepare"] || [path isEqualToString:@"/backend-api/conversation/prepare"])) {
        NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet];
        id json = request.HTTPBody.length ? [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil] : nil; if (json) CECollectExplicitConversationIDs(json, ids, 0);
        NSString *cid = ids.count == 1 ? ids.firstObject : nil; if (conversationIDOut) *conversationIDOut = cid; return cid.length ? @"exact-prepare" : @"staging-prepare";
    }
    if ([method isEqualToString:@"GET"] && [path containsString:@"/conversation/"]) {
        NSString *cid = CEExtractConversationIDFromString(request.URL.absoluteString ?: @""); if (!cid.length) return nil;
        NSString *lcid = cid.lowercaseString;
        if ([path isEqualToString:[NSString stringWithFormat:@"/backend-api/conversation/%@", lcid]] || [path isEqualToString:[NSString stringWithFormat:@"/backend-api/f/conversation/%@", lcid]]) { if (conversationIDOut) *conversationIDOut = cid; return @"detail"; }
    }
    return nil;
}

static void CETraceConversationTransport(NSURLRequest *request, NSURLSession *session, NSURLSessionTask *task, NSString *source) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    NSString *conversationID = nil; NSString *stage = CETraceConversationStage(request, &conversationID); if (!stage.length) return;
    CEConversationIdentityTraceLog(@"NET-REENTRY-TRANSPORT", @"source=%@ stage=%@ method=%@ path=%@ target=%@ bodyKeys=%@ session=%@ sessionClass=%@ task=%@ taskClass=%@ taskState=%ld",
        source ?: @"<none>", stage, request.HTTPMethod ?: @"GET", request.URL.path ?: @"/", conversationID ?: @"<none>", CETraceRequestBodyKeys(request),
        CETraceNetworkToken(session, @"session"), session ? NSStringFromClass(session.class) : @"<none>", CETraceNetworkToken(task, @"task"), task ? NSStringFromClass(task.class) : @"<none>", task ? (long)task.state : -1L);
}

static NSString *CETraceScalar(id value) {
    if ([value isKindOfClass:NSString.class]) { NSString *text = value; return text.length <= 120 ? text : @"<string>"; }
    if ([value isKindOfClass:NSNumber.class]) return [value description];
    return @"<nil>";
}

static NSString *CETraceConversationResponseStructure(NSData *data, NSURLRequest *request) {
    if (!data.length) return @"data=<empty>";
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return [NSString stringWithFormat:@"jsonClass=%@", json ? NSStringFromClass([json class]) : @"<invalid-json>"];
    NSDictionary *root = json; NSArray<NSString *> *rootKeys = CETraceSortedJSONKeys(root); NSDictionary *container = [root[@"conversation"] isKindOfClass:NSDictionary.class] ? root[@"conversation"] : root; NSArray<NSString *> *containerKeys = CETraceSortedJSONKeys(container);
    NSString *conversationID = [container[@"id"] isKindOfClass:NSString.class] ? CEExtractConversationIDFromString(container[@"id"]) : nil; if (!conversationID.length && [container[@"conversation_id"] isKindOfClass:NSString.class]) conversationID = CEExtractConversationIDFromString(container[@"conversation_id"]);
    NSDictionary *mapping = [container[@"mapping"] isKindOfClass:NSDictionary.class] ? container[@"mapping"] : nil; NSString *currentNode = [container[@"current_node"] isKindOfClass:NSString.class] ? container[@"current_node"] : nil; NSDictionary *node = currentNode.length && [mapping[currentNode] isKindOfClass:NSDictionary.class] ? mapping[currentNode] : nil; NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil; NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : nil; NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : nil; NSDictionary *content = [message[@"content"] isKindOfClass:NSDictionary.class] ? message[@"content"] : nil; NSArray *parts = [content[@"parts"] isKindOfClass:NSArray.class] ? content[@"parts"] : nil;
    NSString *requestTarget = nil; CETraceConversationStage(request, &requestTarget);
    return [NSString stringWithFormat:@"requestTarget=%@ rootKeys=%@ containerKeys=%@ conversationID=%@ currentNode=%@ mapping=%lu messageID=%@ role=%@ status=%@ endTurn=%@ updateTime=%@ createTime=%@ finishTime=%@ contentType=%@ parts=%lu",
        requestTarget ?: @"<none>", rootKeys.count ? [rootKeys componentsJoinedByString:@","] : @"<none>", containerKeys.count ? [containerKeys componentsJoinedByString:@","] : @"<none>", conversationID ?: @"<none>", currentNode ?: @"<none>", (unsigned long)mapping.count,
        [message[@"id"] isKindOfClass:NSString.class] ? message[@"id"] : @"<none>", [author[@"role"] isKindOfClass:NSString.class] ? author[@"role"] : @"<none>", [message[@"status"] isKindOfClass:NSString.class] ? message[@"status"] : @"<none>", CETraceScalar(message[@"end_turn"]), CETraceScalar(container[@"update_time"]), CETraceScalar(message[@"create_time"]), CETraceScalar(metadata[@"finish_time"]), [content[@"content_type"] isKindOfClass:NSString.class] ? content[@"content_type"] : @"<none>", (unsigned long)parts.count];
}

static void CETraceConversationResponse(NSURLRequest *request, NSURLResponse *response, NSData *data, NSError *error, NSString *source, NSURLSession *session, NSURLSessionTask *task) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    NSString *conversationID = nil; NSString *stage = CETraceConversationStage(request, &conversationID); if (!stage.length) return;
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    NSString *mime = response.MIMEType.length ? response.MIMEType : @"<none>";
    NSString *structure = [stage isEqualToString:@"detail"] && !error && http.statusCode >= 200 && http.statusCode < 300 ? CETraceConversationResponseStructure(data, request) : ([data length] ? [NSString stringWithFormat:@"jsonKeys=%@", [CETraceSortedJSONKeys([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]) componentsJoinedByString:@","] ?: @"<none>"] : @"data=<empty>");
    CEConversationIdentityTraceLog(@"NET-REENTRY-RESP", @"source=%@ stage=%@ target=%@ status=%ld error=%@ bytes=%lu mime=%@ session=%@ task=%@ structure={%@}", source ?: @"<none>", stage, conversationID ?: @"<none>", (long)http.statusCode, error ? [NSString stringWithFormat:@"%@/%ld", error.domain ?: @"error", (long)error.code] : @"<none>", (unsigned long)data.length, mime, CETraceNetworkToken(session, @"session"), CETraceNetworkToken(task, @"task"), structure ?: @"<none>");
}

static NSInteger CETemplateScore(NSURLRequest *request) {
    if (!request.URL || !CERequestHasAuth(request)) return -1000;
    NSString *path = request.URL.path.lowercaseString ?: @"";
    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";
    if ([path containsString:@"/sentinel/"] || [path containsString:@"heartbeat"] || [path containsString:@"/f/conversation/prepare"] || [path hasSuffix:@"/conversation/prepare"]) return -200;
    NSInteger score = 10;
    if ([method isEqualToString:@"GET"]) score += 10;
    if ([path containsString:@"/backend-api/conversations"]) score += 80;
    if ([path containsString:@"/gizmos/"] && [path containsString:@"/conversations"]) score += 85;
    NSString *cid = CEExtractConversationIDFromString(request.URL.absoluteString ?: @"");
    if (cid.length && [path containsString:@"conversation"]) score += 120;
    else if ([path containsString:@"conversation"]) score += 35;
    return score;
}

static NSURLSession *CEFindSessionForTask(NSURLSessionTask *task) {
    NSURLSession *associated = CESessionForTask(task);
    if (associated) return associated;
    @try {
        for (Class cls = object_getClass(task); cls; cls = class_getSuperclass(cls)) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(cls, &count);
            for (unsigned int i = 0; i < count; i++) {
                Ivar ivar = ivars[i];
                const char *type = ivar_getTypeEncoding(ivar);
                if (!type || type[0] != '@') continue;
                id value = object_getIvar(task, ivar);
                if ([value isKindOfClass:NSURLSession.class]) { free(ivars); return value; }
            }
            free(ivars);
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}

@interface CENetworkObserver ()
@property (nonatomic, strong, nullable) NSURLRequest *requestTemplate;
@property (nonatomic, weak, nullable) NSURLSession *requestSession;
@property (nonatomic, copy, nullable) NSString *baseOrigin;
@property (nonatomic, strong) NSMutableSet<NSString *> *mutableProjectIDs;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableRecentEvents;
@property (nonatomic) NSInteger templateScore;
- (BOOL)isChatGPTRequest:(NSURLRequest *)request;
- (NSURLRequest *)cleanInternalRequestIfNeeded:(NSURLRequest *)request internal:(BOOL *)internal;
- (void)observeRequest:(NSURLRequest *)request session:(nullable NSURLSession *)session;
- (void)observeResponseData:(NSData *)data response:(NSURLResponse *)response request:(NSURLRequest *)request;
- (void)addEvent:(NSString *)event;
@end

@interface NSObject (ChatGPTEnhancerSessionDelegateCapture)
- (void)ce_capture_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
- (void)ce_capture_URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
@end

static void CEInstallDelegateHook(Class cls, SEL originalSelector, SEL replacementSelector) {
    if (!cls) return;
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacementSource = class_getInstanceMethod(NSObject.class, replacementSelector);
    if (!original || !replacementSource) return;
    class_addMethod(cls, originalSelector, method_getImplementation(original), method_getTypeEncoding(original));
    class_addMethod(cls, replacementSelector, method_getImplementation(replacementSource), method_getTypeEncoding(original));
    Method localOriginal = class_getInstanceMethod(cls, originalSelector);
    Method localReplacement = class_getInstanceMethod(cls, replacementSelector);
    if (localOriginal && localReplacement) method_exchangeImplementations(localOriginal, localReplacement);
}

static void CEInstallSessionDelegateCapture(id delegate) {
    if (!delegate) return;
    Class cls = [delegate class];
    if (!cls || [objc_getAssociatedObject(cls, CEDelegateHookedKey) boolValue]) return;
    objc_setAssociatedObject(cls, CEDelegateHookedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CEInstallDelegateHook(cls, @selector(URLSession:dataTask:didReceiveData:), @selector(ce_capture_URLSession:dataTask:didReceiveData:));
    CEInstallDelegateHook(cls, @selector(URLSession:task:didCompleteWithError:), @selector(ce_capture_URLSession:task:didCompleteWithError:));
}

@implementation CENetworkObserver
+ (instancetype)shared {
    static CENetworkObserver *v; static dispatch_once_t once;
    dispatch_once(&once, ^{ v = [CENetworkObserver new]; v.mutableProjectIDs = [NSMutableSet set]; v.mutableRecentEvents = [NSMutableArray array]; v.templateScore = NSIntegerMin; });
    return v;
}
- (NSSet<NSString *> *)knownProjectIDs { @synchronized (self) { return [self.mutableProjectIDs copy]; } }
- (NSArray<NSString *> *)recentEvents { @synchronized (self) { return [self.mutableRecentEvents copy]; } }
- (void)addEvent:(NSString *)event {
    if (!event.length) return;
    @synchronized (self) {
        NSString *line = [NSString stringWithFormat:@"%@ %@", @((long long)(NSDate.date.timeIntervalSince1970 * 1000)), event];
        [self.mutableRecentEvents addObject:line];
        while (self.mutableRecentEvents.count > 120) [self.mutableRecentEvents removeObjectAtIndex:0];
    }
}
- (BOOL)hasUsableTemplate {
    if (!self.requestTemplate || !self.requestSession) return NO;
    return CERequestHasAuth(self.requestTemplate);
}

- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CESwizzleClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:), @selector(ce_sessionWithConfiguration:delegate:delegateQueue:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(initWithConfiguration:delegate:delegateQueue:), @selector(ce_initWithConfiguration:delegate:delegateQueue:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:), @selector(ce_dataTaskWithRequest:completionHandler:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:), @selector(ce_dataTaskWithRequest:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(dataTaskWithURL:completionHandler:), @selector(ce_dataTaskWithURL:completionHandler:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(dataTaskWithURL:), @selector(ce_dataTaskWithURL:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(uploadTaskWithRequest:fromData:completionHandler:), @selector(ce_uploadTaskWithRequest:fromData:completionHandler:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(uploadTaskWithRequest:fromData:), @selector(ce_uploadTaskWithRequest:fromData:));
        CESwizzleInstanceMethod(NSURLSessionTask.class, @selector(resume), @selector(ce_resume));
    });
}

- (BOOL)isChatGPTRequest:(NSURLRequest *)request {
    NSString *host = request.URL.host.lowercaseString ?: @"";
    if (![host containsString:@"chatgpt"] && ![host containsString:@"openai"]) return NO;
    NSString *path = request.URL.path.lowercaseString ?: @"";
    return [path containsString:@"backend-api"] || [path containsString:@"conversation"] || [path containsString:@"gizmo"];
}

- (NSURLRequest *)cleanInternalRequestIfNeeded:(NSURLRequest *)request internal:(BOOL *)internal {
    NSString *marker = [request valueForHTTPHeaderField:CEInternalHeader];
    if (![marker isEqualToString:@"1"]) { if (internal) *internal = NO; return request; }
    NSMutableURLRequest *copy = [request mutableCopy]; [copy setValue:nil forHTTPHeaderField:CEInternalHeader];
    if (internal) *internal = YES; return copy;
}

- (void)observeRequest:(NSURLRequest *)request session:(NSURLSession *)session {
    if (![self isChatGPTRequest:request]) return;
    NSURL *url = request.URL; if (!url) return;
    CEConversationIdentityTraceLogRequest(request);
    CEApplyExplicitConversationInitIdentity(request);
    NSString *path = url.path ?: @"";
    NSInteger score = CETemplateScore(request);
    if (session) self.requestSession = session;
    [self addEvent:[NSString stringWithFormat:@"REQ %@ %@ session=%@ score=%ld", request.HTTPMethod ?: @"GET", path, session ? @"YES" : @"NO", (long)score]];

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (components.scheme.length && components.host.length) self.baseOrigin = [NSString stringWithFormat:@"%@://%@%@", components.scheme, components.host, components.port ? [NSString stringWithFormat:@":%@", components.port] : @""];

    if (score >= 0 && score >= self.templateScore) {
        NSMutableURLRequest *copy = [request mutableCopy];
        copy.HTTPBody = nil;
        [copy setValue:nil forHTTPHeaderField:@"X-OpenAI-Target-Path"];
        [copy setValue:nil forHTTPHeaderField:@"X-OpenAI-Target-Route"];
        self.requestTemplate = copy;
        self.templateScore = score;
        [self addEvent:[NSString stringWithFormat:@"TEMPLATE %@ score=%ld session=%@", path, (long)score, self.requestSession ? @"YES" : @"NO"]];
        [[NSNotificationCenter defaultCenter] postNotificationName:CENetworkTemplateDidChangeNotification object:self];
    }

    static NSRegularExpression *projectRE; static dispatch_once_t once;
    dispatch_once(&once, ^{ projectRE = [NSRegularExpression regularExpressionWithPattern:@"/gizmos/(g-p-[^/]+)/conversations" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *m = [projectRE firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (m.numberOfRanges > 1) { NSString *pid = [path substringWithRange:[m rangeAtIndex:1]]; @synchronized (self) { [self.mutableProjectIDs addObject:pid]; } }
}

- (void)observeResponseData:(NSData *)data response:(NSURLResponse *)response request:(NSURLRequest *)request {
    if (![self isChatGPTRequest:request]) return;
    CEConversationIdentityTraceLogResponse(request, response, nil);
    CETraceConversationResponse(request, response, data, nil, @"observer-response", self.requestSession, nil);
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    [self addEvent:[NSString stringWithFormat:@"RESP %ld %@ bytes=%lu", (long)http.statusCode, request.URL.path ?: @"", (unsigned long)data.length]];
    if (!data.length || (http && (http.statusCode < 200 || http.statusCode >= 300))) return;
    [[CECatalog shared] ingestResponseData:data requestURL:(response.URL ?: request.URL)];
}
@end

@implementation NSObject (ChatGPTEnhancerSessionDelegateCapture)
- (void)ce_capture_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (!CEIsInternalTask(dataTask)) {
        CEAssociateSession(dataTask, session);
        NSURLRequest *request = dataTask.currentRequest ?: dataTask.originalRequest;
        if (request) [[CENetworkObserver shared] observeRequest:request session:session];
        if (request && [[CENetworkObserver shared] isChatGPTRequest:request] && data.length) {
            NSMutableData *buffer = objc_getAssociatedObject(dataTask, CEResponseBufferKey);
            if (!buffer) { buffer = [NSMutableData data]; objc_setAssociatedObject(dataTask, CEResponseBufferKey, buffer, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            if (buffer.length + data.length <= 64 * 1024 * 1024) [buffer appendData:data];
        }
    }
    [self ce_capture_URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)ce_capture_URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!CEIsInternalTask(task)) {
        CEAssociateSession(task, session);
        NSURLRequest *request = task.currentRequest ?: task.originalRequest;
        if (request) [[CENetworkObserver shared] observeRequest:request session:session];
        NSData *captured = objc_getAssociatedObject(task, CEResponseBufferKey);
        if (request) CETraceConversationResponse(request, task.response, captured, error, @"delegate-completion", session, task);
        if (error && request) CEConversationIdentityTraceLogResponse(request, task.response, error);
        if (!error && captured.length && request) [[CENetworkObserver shared] observeResponseData:captured response:task.response request:request];
    }
    objc_setAssociatedObject(task, CEResponseBufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self ce_capture_URLSession:session task:task didCompleteWithError:error];
}
@end

@implementation NSURLSession (ChatGPTEnhancerNetwork)
+ (NSURLSession *)ce_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    CEInstallSessionDelegateCapture(delegate);
    return [self ce_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}
- (instancetype)ce_initWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    CEInstallSessionDelegateCapture(delegate);
    return [self ce_initWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}
- (NSURLSessionDataTask *)ce_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) { CEConversationIdentityTraceLogTaskCreation(clean, @"dataTaskWithRequest:completion"); [[CENetworkObserver shared] observeRequest:clean session:self]; }
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!internal) CETraceConversationResponse(clean, response, data, error, @"completion-handler", self, nil);
        if (!internal && error) CEConversationIdentityTraceLogResponse(clean, response, error);
        if (!internal && !error) [[CENetworkObserver shared] observeResponseData:data response:response request:clean];
        if (completionHandler) completionHandler(data, response, error);
    };
    NSURLSessionDataTask *task = [self ce_dataTaskWithRequest:clean completionHandler:wrapped]; CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task); else CETraceConversationTransport(clean, self, task, @"create-dataTaskWithRequest-completion"); return task;
}
- (NSURLSessionDataTask *)ce_dataTaskWithRequest:(NSURLRequest *)request {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) { CEConversationIdentityTraceLogTaskCreation(clean, @"dataTaskWithRequest"); [[CENetworkObserver shared] observeRequest:clean session:self]; }
    NSURLSessionDataTask *task = [self ce_dataTaskWithRequest:clean]; CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task); else CETraceConversationTransport(clean, self, task, @"create-dataTaskWithRequest"); return task;
}
- (NSURLSessionDataTask *)ce_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:url]; CEConversationIdentityTraceLogTaskCreation(request, @"dataTaskWithURL:completion"); [[CENetworkObserver shared] observeRequest:request session:self];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        CETraceConversationResponse(request, response, data, error, @"completion-handler-url", self, nil);
        if (error) CEConversationIdentityTraceLogResponse(request, response, error);
        if (!error) [[CENetworkObserver shared] observeResponseData:data response:response request:request]; if (completionHandler) completionHandler(data, response, error);
    };
    NSURLSessionDataTask *task = [self ce_dataTaskWithURL:url completionHandler:wrapped]; CEAssociateSession(task, self); CETraceConversationTransport(request, self, task, @"create-dataTaskWithURL-completion"); return task;
}
- (NSURLSessionDataTask *)ce_dataTaskWithURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest requestWithURL:url]; CEConversationIdentityTraceLogTaskCreation(request, @"dataTaskWithURL"); [[CENetworkObserver shared] observeRequest:request session:self];
    NSURLSessionDataTask *task = [self ce_dataTaskWithURL:url]; CEAssociateSession(task, self); CETraceConversationTransport(request, self, task, @"create-dataTaskWithURL"); return task;
}
- (NSURLSessionUploadTask *)ce_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    NSMutableURLRequest *observed = [clean mutableCopy]; observed.HTTPBody = bodyData;
    if (!internal) { CEConversationIdentityTraceLogTaskCreation(observed, @"uploadTaskWithRequest:fromData:completion"); [[CENetworkObserver shared] observeRequest:observed session:self]; }
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!internal) CETraceConversationResponse(observed, response, data, error, @"upload-completion-handler", self, nil);
        if (!internal && error) CEConversationIdentityTraceLogResponse(clean, response, error);
        if (!internal && !error) [[CENetworkObserver shared] observeResponseData:data response:response request:clean]; if (completionHandler) completionHandler(data, response, error);
    };
    NSURLSessionUploadTask *task = [self ce_uploadTaskWithRequest:clean fromData:bodyData completionHandler:wrapped]; CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task); else CETraceConversationTransport(observed, self, task, @"create-uploadTaskWithRequest-completion"); return task;
}
- (NSURLSessionUploadTask *)ce_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal]; NSMutableURLRequest *observed = [clean mutableCopy]; observed.HTTPBody = bodyData;
    if (!internal) { CEConversationIdentityTraceLogTaskCreation(observed, @"uploadTaskWithRequest:fromData"); [[CENetworkObserver shared] observeRequest:observed session:self]; }
    NSURLSessionUploadTask *task = [self ce_uploadTaskWithRequest:clean fromData:bodyData]; CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task); else CETraceConversationTransport(observed, self, task, @"create-uploadTaskWithRequest"); return task;
}
@end

@implementation NSURLSessionTask (ChatGPTEnhancerNetworkTask)
- (void)ce_resume {
    if (!CEIsInternalTask(self)) {
        NSURLSession *session = CEFindSessionForTask(self);
        if (session) CEAssociateSession(self, session);
        NSURLRequest *request = self.currentRequest ?: self.originalRequest;
        if (request) { CETraceConversationTransport(request, session, self, @"resume"); [[CENetworkObserver shared] observeRequest:request session:session]; }
    }
    [self ce_resume];
}
@end