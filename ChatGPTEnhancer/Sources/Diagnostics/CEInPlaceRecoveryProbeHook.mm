#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CEInPlaceRecoveryProbe.h"
#import "CERecoveryDiagnostics.h"
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"

static NSDate *CEInPlaceProbeLastAutoDate = nil;

@interface CEAPIClient (ChatGPTEnhancerInPlaceProbe)
- (void)ce_inplaceProbe_getPath:(NSString *)path progress:(CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion;
@end

@implementation CEAPIClient (ChatGPTEnhancerInPlaceProbe)
- (void)ce_inplaceProbe_getPath:(NSString *)path progress:(CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion {
    NSString *conversationID = [CEConversationContext shared].conversationID;
    NSString *encoded = conversationID.length ? [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] : nil;
    NSString *expected = encoded.length ? [NSString stringWithFormat:@"/backend-api/conversation/%@", encoded] : nil;
    if (expected.length && [path hasPrefix:expected]) {
        NSDate *now = NSDate.date;
        if (!CEInPlaceProbeLastAutoDate || [now timeIntervalSinceDate:CEInPlaceProbeLastAutoDate] >= 4.0) {
            CEInPlaceProbeLastAutoDate = now;
            CERecoveryDiagnosticLog(@"INPLACE30-HOOK", @"current conversation GET observed path=%@; capturing active native state before request", path);
            CEInPlaceRecoveryProbe(@"current-conversation GET");
        }
    }
    [self ce_inplaceProbe_getPath:path progress:progress completion:completion];
}
@end

__attribute__((constructor)) static void CEInPlaceRecoveryProbeHookEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class cls = CEAPIClient.class;
            Method original = class_getInstanceMethod(cls, @selector(getPath:progress:completion:));
            Method replacement = class_getInstanceMethod(cls, @selector(ce_inplaceProbe_getPath:progress:completion:));
            if (!original || !replacement) { CERecoveryDiagnosticLog(@"INPLACE30-HOOK", @"install failed original=%p replacement=%p", original, replacement); return; }
            method_exchangeImplementations(original, replacement);
            CERecoveryDiagnosticLog(@"INPLACE30-HOOK", @"installed current-conversation GET probe; no navigation and no native method invocation");
        });
    }
}
