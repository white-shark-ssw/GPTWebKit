#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Network/CENetworkObserver.h"
#import "../Storage/CECatalog.h"
#import "../UI/CEEnhancerUI.h"

static void CEStartEnhancer(void) {
    if (!CETargetApp()) return;
    @try {
        [[CENetworkObserver shared] start];
        [[CECatalog shared] start];
        [[CEEnhancerUI shared] start];
        NSLog(@"[ChatGPTEnhancer] %@ started for %@ %@", CEVersion, NSBundle.mainBundle.bundleIdentifier, [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown");
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
