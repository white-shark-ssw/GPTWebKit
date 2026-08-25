#import "CEModelContextResolver.h"
#import "../Core/CECore.h"
#import <objc/runtime.h>

static IMP CEModelResolverOriginalObserveResponseIMP = NULL;
static NSMutableDictionary<NSString *, NSNumber *> *CEModelResolverCapacities;
static dispatch_queue_t CEModelResolverQueue;
static BOOL CEModelResolverInstalled = NO;

static NSString *CEModelResolverString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

static NSUInteger CEModelResolverDirectCapacity(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return 0;
    for (NSString *key in @[@"context_window", @"context_window_size", @"max_context_tokens", @"max_context_length", @"max_tokens"]) {
        id raw = dictionary[key]; NSUInteger value = [raw respondsToSelector:@selector(unsignedIntegerValue)] ? [raw unsignedIntegerValue] : 0;
        if (value >= 4096 && value <= 2000000) return value;
    }
    return 0;
}

static void CEModelResolverScan(id value, NSUInteger depth, NSMutableDictionary<NSString *, NSNumber *> *output) {
    if (!value || value == NSNull.null || depth > 7) return;
    if ([value isKindOfClass:NSArray.class]) { for (id child in (NSArray *)value) CEModelResolverScan(child, depth + 1, output); return; }
    if (![value isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dictionary = value;
    NSString *slug = nil;
    for (NSString *key in @[@"slug", @"model_slug", @"id", @"model_id"]) { slug = CEModelResolverString(dictionary[key]); if (slug.length) break; }
    NSUInteger capacity = CEModelResolverDirectCapacity(dictionary);
    if (slug.length && capacity) output[slug.lowercaseString] = @(capacity);
    for (id child in dictionary.allValues) if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) CEModelResolverScan(child, depth + 1, output);
}

static NSUInteger CEModelResolverFallbackCapacity(NSString *model, NSString **sourceOut) {
    NSString *lower = model.lowercaseString ?: @"";
    if ([lower containsString:@"gpt-5.6"] || [lower containsString:@"gpt-5-6"] || [lower containsString:@"gpt-5.5"] || [lower containsString:@"gpt-5-5"] || ([lower containsString:@"gpt-5.4"] && ![lower containsString:@"mini"] && ![lower containsString:@"nano"]) || ([lower containsString:@"gpt-5-4"] && ![lower containsString:@"mini"] && ![lower containsString:@"nano"])) { if (sourceOut) *sourceOut = @"fallback-model-docs=1050000"; return 1050000; }
    if ([lower containsString:@"gpt-5.4-mini"] || [lower containsString:@"gpt-5-4-mini"] || [lower containsString:@"gpt-5.4-nano"] || [lower containsString:@"gpt-5-4-nano"] || [lower containsString:@"gpt-5.3"] || [lower containsString:@"gpt-5-3"] || [lower containsString:@"gpt-5.2"] || [lower containsString:@"gpt-5-2"] || [lower containsString:@"gpt-5.1"] || [lower containsString:@"gpt-5-1"] || [lower containsString:@"chat-latest"]) { if (sourceOut) *sourceOut = @"fallback-model-family=400000"; return 400000; }
    if ([lower containsString:@"gpt-4.1"] || [lower containsString:@"gpt-4-1"]) { if (sourceOut) *sourceOut = @"fallback-gpt-4.1=1047576"; return 1047576; }
    if ([lower containsString:@"gpt-4o"] || [lower containsString:@"gpt-4-o"]) { if (sourceOut) *sourceOut = @"fallback-gpt-4o=128000"; return 128000; }
    if ([lower hasPrefix:@"o3"] || [lower hasPrefix:@"o4"]) { if (sourceOut) *sourceOut = @"fallback-o3-o4=200000"; return 200000; }
    if (sourceOut) *sourceOut = model.length ? [NSString stringWithFormat:@"unknown-model:%@ fallback=128000", model] : @"model-unavailable fallback=128000";
    return 128000;
}

NSUInteger CEChatGPTContextCapacityForModel(NSString *model, NSString **sourceOut) {
    NSString *lower = model.lowercaseString ?: @"";
    @synchronized (CEModelResolverCapacities) {
        NSNumber *exact = CEModelResolverCapacities[lower];
        if (exact.unsignedIntegerValue) { if (sourceOut) *sourceOut = [NSString stringWithFormat:@"official-app-model-catalog:%@", lower]; return exact.unsignedIntegerValue; }
        __block NSString *bestKey = nil; __block NSNumber *bestValue = nil;
        [CEModelResolverCapacities enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {
            if (!key.length || !lower.length) return;
            if (([lower containsString:key] || [key containsString:lower]) && (!bestKey || key.length > bestKey.length)) { bestKey = key; bestValue = value; }
        }];
        if (bestValue.unsignedIntegerValue) { if (sourceOut) *sourceOut = [NSString stringWithFormat:@"official-app-model-catalog:%@", bestKey]; return bestValue.unsignedIntegerValue; }
    }
    return CEModelResolverFallbackCapacity(model, sourceOut);
}

static void CEModelResolverParseResponse(NSData *data, NSURLResponse *response, NSURLRequest *request) {
    NSString *path = (response.URL ?: request.URL).path.lowercaseString ?: @"";
    if (![path containsString:@"/models"] || !data.length) return;
    dispatch_async(CEModelResolverQueue, ^{
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; if (!root) return;
        NSMutableDictionary<NSString *, NSNumber *> *found = [NSMutableDictionary dictionary]; CEModelResolverScan(root, 0, found); if (!found.count) return;
        @synchronized (CEModelResolverCapacities) { [CEModelResolverCapacities addEntriesFromDictionary:found]; }
        NSLog(@"[ChatGPTEnhancer][MODEL-CONTEXT] captured %lu model capacities from %@", (unsigned long)found.count, path);
        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:CECatalogDidChangeNotification object:nil]; });
    });
}

static void CEModelResolverObserveResponse(id self, SEL _cmd, NSData *data, NSURLResponse *response, NSURLRequest *request) {
    if (CEModelResolverOriginalObserveResponseIMP) ((void (*)(id, SEL, NSData *, NSURLResponse *, NSURLRequest *))CEModelResolverOriginalObserveResponseIMP)(self, _cmd, data, response, request);
    CEModelResolverParseResponse(data, response, request);
}

void CEStartModelContextResolver(void) {
    if (CEModelResolverInstalled) return;
    CEModelResolverInstalled = YES;
    CEModelResolverQueue = dispatch_queue_create("com.whiteshark.chatgptenhancer.model-context", DISPATCH_QUEUE_SERIAL);
    CEModelResolverCapacities = [NSMutableDictionary dictionary];
    Class cls = NSClassFromString(@"CENetworkObserver"); SEL selector = NSSelectorFromString(@"observeResponseData:response:request:"); Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) { NSLog(@"[ChatGPTEnhancer][MODEL-CONTEXT] observer capture unavailable"); return; }
    CEModelResolverOriginalObserveResponseIMP = method_getImplementation(method); method_setImplementation(method, (IMP)CEModelResolverObserveResponse);
    NSLog(@"[ChatGPTEnhancer][MODEL-CONTEXT] official model catalog capture installed");
}

__attribute__((constructor)) static void CEModelContextResolverEntry(void) {
    @autoreleasepool { if (!CETargetApp()) return; CEStartModelContextResolver(); }
}
