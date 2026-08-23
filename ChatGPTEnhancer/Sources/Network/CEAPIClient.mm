#import "CEAPIClient.h"
#import "CENetworkObserver.h"
#import "../Core/CECore.h"

static NSString * const CEInternalHeader = @"X-ChatGPTEnhancer-Internal";

@implementation CEAPIClient {
    NSURLSession *_fallbackSession;
}

+ (instancetype)shared { static CEAPIClient *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEAPIClient new]; }); return v; }
- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *c = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        c.timeoutIntervalForRequest = 90; c.timeoutIntervalForResource = 240; c.HTTPShouldSetCookies = YES;
        _fallbackSession = [NSURLSession sessionWithConfiguration:c];
    }
    return self;
}
- (BOOL)isReady { return [CENetworkObserver shared].hasUsableTemplate; }
- (void)getPath:(NSString *)path progress:(CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion { [self performMethod:@"GET" path:path body:nil attempt:0 progress:progress completion:completion]; }
- (void)patchPath:(NSString *)path jsonBody:(NSDictionary *)body progress:(CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion {
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [self performMethod:@"PATCH" path:path body:data attempt:0 progress:progress completion:completion];
}

- (NSMutableURLRequest *)requestForMethod:(NSString *)method path:(NSString *)path body:(NSData *)body {
    CENetworkObserver *observer = [CENetworkObserver shared]; NSURLRequest *requestTemplate = observer.requestTemplate;
    NSString *origin = observer.baseOrigin.length ? observer.baseOrigin : @"https://chatgpt.com";
    NSURL *url = [NSURL URLWithString:path relativeToURL:[NSURL URLWithString:[origin stringByAppendingString:@"/"]]];
    if ([path hasPrefix:@"/"]) url = [NSURL URLWithString:[origin stringByAppendingString:path]];
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:180];
    request.HTTPMethod = method; request.HTTPBody = body;
    NSDictionary *sourceHeaders = requestTemplate.allHTTPHeaderFields ?: @{};
    for (NSString *key in sourceHeaders) {
        NSString *lower = key.lowercaseString;
        if ([lower isEqualToString:@"content-length"] || [lower isEqualToString:@"host"] || [lower isEqualToString:@"accept-encoding"]) continue;
        [request setValue:sourceHeaders[key] forHTTPHeaderField:key];
    }
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSString *targetPath = [path componentsSeparatedByString:@"?"].firstObject ?: path;
    [request setValue:targetPath forHTTPHeaderField:@"x-openai-target-path"];
    [request setValue:@"1" forHTTPHeaderField:CEInternalHeader];
    return request;
}

- (void)performMethod:(NSString *)method path:(NSString *)path body:(NSData *)body attempt:(NSUInteger)attempt progress:(CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion {
    CENetworkObserver *observer = [CENetworkObserver shared];
    NSMutableURLRequest *request = [self requestForMethod:method path:path body:body];
    NSURLSession *session = observer.requestSession ?: _fallbackSession;
    if (!request || ![self isReady] || session == _fallbackSession) {
        NSError *e = [NSError errorWithDomain:@"ChatGPTEnhancer" code:-20 userInfo:@{NSLocalizedDescriptionKey:@"尚未捕获到官方 ChatGPT 的可复用网络会话，请先返回会话列表，再重新进入一次会话。"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, e); }); return;
    }
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSInteger status = http.statusCode;
        BOOL transportRetry = error && attempt < 3;
        BOOL serverRetry = [@[@500,@502,@503,@504] containsObject:@(status)] && attempt < 3;
        BOOL authRetry = [@[@401,@403] containsObject:@(status)] && attempt < 1;
        BOOL rateRetry = status == 429 && attempt < 3;
        if (transportRetry || serverRetry || authRetry || rateRetry) {
            NSArray *delays = @[@0.7,@1.5,@3.0]; NSTimeInterval delay = [delays[MIN(attempt, delays.count - 1)] doubleValue];
            if (rateRetry) {
                NSString *retryAfter = http.allHeaderFields[@"Retry-After"] ?: http.allHeaderFields[@"retry-after"];
                if (retryAfter.doubleValue > 0) delay = MIN(MAX(retryAfter.doubleValue, 0.7), 10.0);
            }
            NSString *reason = serverRetry ? @"服务器读取超时" : authRetry ? @"认证环境需要刷新" : rateRetry ? @"请求频率受限" : @"网络请求失败";
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress([NSString stringWithFormat:@"%@，正在重试 %lu/3…", reason, (unsigned long)(attempt + 1)]); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [self performMethod:method path:path body:body attempt:attempt + 1 progress:progress completion:completion];
            });
            return;
        }
        if (error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, http, error); }); return; }
        if (status < 200 || status >= 300) {
            NSString *detail = data.length ? [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN((NSUInteger)800, data.length))] encoding:NSUTF8StringEncoding] : @"";
            NSString *message = [NSString stringWithFormat:@"ChatGPT 请求失败（HTTP %ld）%@", (long)status, detail.length ? [NSString stringWithFormat:@"：%@", detail] : @""];
            if (status == 403 && [detail containsString:@"Request is not allowed"]) message = @"官方 ChatGPT 的网络防护拒绝了插件发起的副本请求。请返回会话列表再进入当前会话后重试；alpha4 会优先复用官方 App 自己的网络会话。";
            NSError *e = [NSError errorWithDomain:@"ChatGPTEnhancer" code:status userInfo:@{NSLocalizedDescriptionKey:message}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, http, e); }); return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(data, http, nil); });
    }];
    [task resume];
}
@end
