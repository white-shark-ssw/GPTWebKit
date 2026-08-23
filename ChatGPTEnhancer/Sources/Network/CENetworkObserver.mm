#import "CENetworkObserver.h"
#import "../Core/CECore.h"
#import <objc/runtime.h>

static NSString * const CEInternalHeader = @"X-ChatGPTEnhancer-Internal";

@interface CENetworkObserver ()
@property (nonatomic, strong, nullable) NSURLRequest *requestTemplate;
@property (nonatomic, copy, nullable) NSString *baseOrigin;
@property (nonatomic, strong) NSMutableSet<NSString *> *mutableProjectIDs;
@end

@implementation CENetworkObserver
+ (instancetype)shared { static CENetworkObserver *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CENetworkObserver new]; v.mutableProjectIDs = [NSMutableSet set]; }); return v; }
- (NSSet<NSString *> *)knownProjectIDs { @synchronized (self) { return [self.mutableProjectIDs copy]; } }
- (BOOL)hasUsableTemplate {
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
        CESwizzleInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:), @selector(ce_dataTaskWithRequest:completionHandler:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:), @selector(ce_dataTaskWithRequest:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(uploadTaskWithRequest:fromData:completionHandler:), @selector(ce_uploadTaskWithRequest:fromData:completionHandler:));
        CESwizzleInstanceMethod(NSURLSession.class, @selector(uploadTaskWithRequest:fromData:), @selector(ce_uploadTaskWithRequest:fromData:));
    });
}

- (BOOL)isChatGPTRequest:(NSURLRequest *)request {
    NSString *host = request.URL.host.lowercaseString ?: @"";
    if (![host containsString:@"chatgpt"] && ![host containsString:@"openai"]) return NO;
    NSString *path = request.URL.path ?: @"";
    return [path containsString:@"backend-api"] || [path containsString:@"conversation"] || [path containsString:@"gizmo"];
}

- (NSURLRequest *)cleanInternalRequestIfNeeded:(NSURLRequest *)request internal:(BOOL *)internal {
    NSString *marker = [request valueForHTTPHeaderField:CEInternalHeader];
    if (![marker isEqualToString:@"1"]) { if (internal) *internal = NO; return request; }
    NSMutableURLRequest *copy = [request mutableCopy]; [copy setValue:nil forHTTPHeaderField:CEInternalHeader];
    if (internal) *internal = YES; return copy;
}

- (void)observeRequest:(NSURLRequest *)request {
    if (![self isChatGPTRequest:request]) return;
    NSURL *url = request.URL; if (!url) return;
    NSString *path = url.path ?: @"";
    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";

    if ([path containsString:@"/backend-api/"] || [path containsString:@"/conversation"]) {
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

    if ([method isEqualToString:@"GET"] && [path rangeOfString:@"/conversation/"].location != NSNotFound && [path rangeOfString:@"gen_title"].location == NSNotFound) {
        NSString *cid = CEExtractConversationIDFromString(url.absoluteString);
        if (cid.length) [[CEConversationContext shared] setConversationID:cid title:nil];
    }

    static NSRegularExpression *projectRE; static dispatch_once_t once; dispatch_once(&once, ^{ projectRE = [NSRegularExpression regularExpressionWithPattern:@"/gizmos/(g-p-[^/]+)/conversations" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *m = [projectRE firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (m.numberOfRanges > 1) {
        NSString *pid = [path substringWithRange:[m rangeAtIndex:1]];
        @synchronized (self) { [self.mutableProjectIDs addObject:pid]; }
    }
}
@end

@implementation NSURLSession (ChatGPTEnhancerNetwork)
- (NSURLSessionDataTask *)ce_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean];
    return [self ce_dataTaskWithRequest:clean completionHandler:completionHandler];
}
- (NSURLSessionDataTask *)ce_dataTaskWithRequest:(NSURLRequest *)request {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean];
    return [self ce_dataTaskWithRequest:clean];
}
- (NSURLSessionUploadTask *)ce_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean];
    return [self ce_uploadTaskWithRequest:clean fromData:bodyData completionHandler:completionHandler];
}
- (NSURLSessionUploadTask *)ce_uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    BOOL internal = NO; NSURLRequest *clean = [[CENetworkObserver shared] cleanInternalRequestIfNeeded:request internal:&internal];
    if (!internal) [[CENetworkObserver shared] observeRequest:clean];
    return [self ce_uploadTaskWithRequest:clean fromData:bodyData];
}
@end
