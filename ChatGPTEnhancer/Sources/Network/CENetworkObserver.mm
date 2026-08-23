#import "CENetworkObserver.h"
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import <objc/runtime.h>

static NSString * const CEInternalHeader = @"X-ChatGPTEnhancer-Internal";
static const void *CEInternalTaskKey = &CEInternalTaskKey;
static const void *CESessionTaskKey = &CESessionTaskKey;
static const void *CEResponseBufferKey = &CEResponseBufferKey;
static const void *CEDelegateHookedKey = &CEDelegateHookedKey;

static void CEMarkInternalTask(NSURLSessionTask *task) { if (task) objc_setAssociatedObject(task, CEInternalTaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL CEIsInternalTask(NSURLSessionTask *task) { return [objc_getAssociatedObject(task, CEInternalTaskKey) boolValue]; }
static void CEAssociateSession(NSURLSessionTask *task, NSURLSession *session) { if (task && session) objc_setAssociatedObject(task, CESessionTaskKey, session, OBJC_ASSOCIATION_ASSIGN); }
static NSURLSession *CESessionForTask(NSURLSessionTask *task) { return task ? objc_getAssociatedObject(task, CESessionTaskKey) : nil; }

@interface CENetworkObserver ()
@property (nonatomic, strong, nullable) NSURLRequest *requestTemplate;
@property (nonatomic, weak, nullable) NSURLSession *requestSession;
@property (nonatomic, copy, nullable) NSString *baseOrigin;
@property (nonatomic, strong) NSMutableSet<NSString *> *mutableProjectIDs;
- (BOOL)isChatGPTRequest:(NSURLRequest *)request;
- (NSURLRequest *)cleanInternalRequestIfNeeded:(NSURLRequest *)request internal:(BOOL *)internal;
- (void)observeRequest:(NSURLRequest *)request session:(nullable NSURLSession *)session;
- (void)observeResponseData:(NSData *)data response:(NSURLResponse *)response request:(NSURLRequest *)request;
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
    Class cls = object_getClass(delegate) ? [delegate class] : Nil;
    if (!cls || [objc_getAssociatedObject(cls, CEDelegateHookedKey) boolValue]) return;
    objc_setAssociatedObject(cls, CEDelegateHookedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CEInstallDelegateHook(cls, @selector(URLSession:dataTask:didReceiveData:), @selector(ce_capture_URLSession:dataTask:didReceiveData:));
    CEInstallDelegateHook(cls, @selector(URLSession:task:didCompleteWithError:), @selector(ce_capture_URLSession:task:didCompleteWithError:));
}

@implementation CENetworkObserver
+ (instancetype)shared { static CENetworkObserver *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CENetworkObserver new]; v.mutableProjectIDs = [NSMutableSet set]; }); return v; }
- (NSSet<NSString *> *)knownProjectIDs { @synchronized (self) { return [self.mutableProjectIDs copy]; } }
- (BOOL)hasUsableTemplate {
    if (!self.requestTemplate || !self.requestSession) return NO;
    NSDictionary *h = self.requestTemplate.allHTTPHeaderFields ?: @{};
    for (NSString *key in h) {
        NSString *lower = key.lowercaseString;
        if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"chatgpt-account-id"] || [lower isEqualToString:@"cookie"]) return YES;
    }
    return NO;
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
    NSString *path = url.path ?: @"";
    if (session) self.requestSession = session;

    if ([path containsString:@"/backend-api/"] || [path.lowercaseString containsString:@"conversation"]) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        if (components.scheme.length && components.host.length) self.baseOrigin = [NSString stringWithFormat:@"%@://%@%@", components.scheme, components.host, components.port ? [NSString stringWithFormat:@":%@", components.port] : @""];
        NSDictionary *headers = request.allHTTPHeaderFields ?: @{};
        BOOL useful = NO;
        for (NSString *key in headers) {
            NSString *lower = key.lowercaseString;
            if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"chatgpt-account-id"] || [lower isEqualToString:@"cookie"]) { useful = YES; break; }
        }
        if (useful) {
            NSMutableURLRequest *requestTemplateCopy = [request mutableCopy]; requestTemplateCopy.HTTPBody = nil;
            self.requestTemplate = requestTemplateCopy;
            [[NSNotificationCenter defaultCenter] postNotificationName:CENetworkTemplateDidChangeNotification object:self];
        }
    }

    if ([path.lowercaseString containsString:@"conversation"] && [path rangeOfString:@"gen_title" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        NSString *cid = CEExtractConversationIDFromString(url.absoluteString);
        if (cid.length) [[CEConversationContext shared] setConversationID:cid title:nil];
    }

    static NSRegularExpression *projectRE; static dispatch_once_t once; dispatch_once(&once, ^{ projectRE = [NSRegularExpression regularExpressionWithPattern:@"/gizmos/(g-p-[^/]+)/conversations" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *m = [projectRE firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (m.numberOfRanges > 1) { NSString *pid = [path substringWithRange:[m rangeAtIndex:1]]; @synchronized (self) { [self.mutableProjectIDs addObject:pid]; } }
}

- (void)observeResponseData:(NSData *)data response:(NSURLResponse *)response request:(NSURLRequest *)request {
    if (!data.length || ![self isChatGPTRequest:request]) return;
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    if (http && (http.statusCode < 200 || http.statusCode >= 300)) return;
    [[CECatalog shared] ingestResponseData:data requestURL:(response.URL ?: request.URL)];
}
@end

@implementation NSObject (ChatGPTEnhancerSessionDelegateCapture)
- (void)ce_capture_URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (!CEIsInternalTask(dataTask)) {
        NSURLRequest *request = dataTask.currentRequest ?: dataTask.originalRequest;
        if (request && [[CENetworkObserver shared] isChatGPTRequest:request] && data.length) {
            NSMutableData *buffer = objc_getAssociatedObject(dataTask, CEResponseBufferKey);
            if (!buffer) { buffer = [NSMutableData data]; objc_setAssociatedObject(dataTask, CEResponseBufferKey, buffer, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            if (buffer.length + data.length <= 64 * 1024 * 1024) [buffer appendData:data];
        }
    }
    [self ce_capture_URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)ce_capture_URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!CEIsInternalTask(task) && !error) {
        NSData *captured = objc_getAssociatedObject(task, CEResponseBufferKey);
        NSURLRequest *request = task.currentRequest ?: task.originalRequest;
        if (captured.length && request) [[CENetworkObserver shared] observeResponseData:captured response:task.response request:request];
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
    if (!internal) [[CENetworkObserver shared] observeRequest:clean session:self];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!internal && !error) [[CENetworkObserver shared] observeResponseData:data response:response request:clean];
        if (completionHandler) completionHandler(data, response, error);
    };
    NSURLSessionDataTask *task = [self ce_dataTaskWithRequest:clean completionHandler:wrapped];
    CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task);
    return task;
}
- (NSURLSessionDataTask *)ce_dataTaskWithRequest:(NSURLRequest *)request {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean session:self];
    NSURLSessionDataTask *task = [self ce_dataTaskWithRequest:clean];
    CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task);
    return task;
}
- (NSURLSessionDataTask *)ce_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:url]; [[CENetworkObserver shared] observeRequest:request session:self];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) [[CENetworkObserver shared] observeResponseData:data response:response request:request];
        if (completionHandler) completionHandler(data, response, error);
    };
    NSURLSessionDataTask *task = [self ce_dataTaskWithURL:url completionHandler:wrapped]; CEAssociateSession(task, self); return task;
}
- (NSURLSessionDataTask *)ce_dataTaskWithURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest requestWithURL:url]; [[CENetworkObserver shared] observeRequest:request session:self];
    NSURLSessionDataTask *task = [self ce_dataTaskWithURL:url]; CEAssociateSession(task, self); return task;
}
- (NSURLSessionUploadTask *)ce_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean session:self];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!internal && !error) [[CENetworkObserver shared] observeResponseData:data response:response request:clean];
        if (completionHandler) completionHandler(data, response, error);
    };
    NSURLSessionUploadTask *task = [self ce_uploadTaskWithRequest:clean fromData:bodyData completionHandler:wrapped];
    CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task); return task;
}
- (NSURLSessionUploadTask *)ce_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean session:self];
    NSURLSessionUploadTask *task = [self ce_uploadTaskWithRequest:clean fromData:bodyData];
    CEAssociateSession(task, self); if (internal) CEMarkInternalTask(task); return task;
}
@end

@implementation NSURLSessionTask (ChatGPTEnhancerNetworkTask)
- (void)ce_resume {
    if (!CEIsInternalTask(self)) {
        NSURLRequest *request = self.currentRequest ?: self.originalRequest;
        if (request) [[CENetworkObserver shared] observeRequest:request session:CESessionForTask(self)];
    }
    [self ce_resume];
}
@end
