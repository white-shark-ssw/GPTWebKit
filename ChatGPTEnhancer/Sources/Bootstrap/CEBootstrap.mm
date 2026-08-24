#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Network/CENetworkObserver.h"
#import "../Storage/CECatalog.h"
#import "../UI/CEEnhancerUI.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "../Diagnostics/CEDiagnostics.h"

static void CEShowLoadedToastWhenReady(NSUInteger attempt) {
    if (CEKeyWindow()) { CEShowMessage(@"ChatGPTEnhancer alpha27-diagnostic 已加载"); return; }
    if (attempt >= 12) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEShowLoadedToastWhenReady(attempt + 1); });
}

static void CEStartEnhancer(void) {
    if (!CETargetApp()) return;
    CERecoveryDiagnosticMark(@"PLUGIN START alpha27-diagnostic");
    @try {
        [[CENetworkObserver shared] start];
        CEInstallActiveConversationDiagnostics();
        [[CECatalog shared] start];
        [[CEEnhancerUI shared] start];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEShowLoadedToastWhenReady(0); });
        NSLog(@"[ChatGPTEnhancer] alpha27-diagnostic started for %@ %@", NSBundle.mainBundle.bundleIdentifier, [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown");
    } @catch (NSException *exception) {
        NSLog(@"[ChatGPTEnhancer] startup exception: %@", exception);
    }
}

__attribute__((constructor)) static void CEEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) CEStartEnhancer();
            else {
                __block id token = nil;
                token = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    if (token) [[NSNotificationCenter defaultCenter] removeObserver:token];
                    CEStartEnhancer();
                }];
            }
        });
    }
}
