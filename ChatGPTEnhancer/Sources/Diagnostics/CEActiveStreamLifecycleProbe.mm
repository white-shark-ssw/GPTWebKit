#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "CEInPlaceRecoveryProbe.h"
#import "CERecoveryDiagnostics.h"

static NSDate *CEActiveStreamProbeLastDate = nil;

static void CEActiveStreamProbeCapture(NSString *reason, NSTimeInterval minimumInterval) {
    NSDate *now = NSDate.date;
    if (CEActiveStreamProbeLastDate && [now timeIntervalSinceDate:CEActiveStreamProbeLastDate] < minimumInterval) return;
    CEActiveStreamProbeLastDate = now;
    CERecoveryDiagnosticLog(@"INPLACE30-LIFECYCLE", @"capture reason=%@ appState=%ld context=%@", reason, (long)UIApplication.sharedApplication.applicationState, [CEConversationContext shared].conversationID ?: @"<nil>");
    CEInPlaceRecoveryProbe(reason);
}

__attribute__((constructor)) static void CEActiveStreamLifecycleProbeEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEActiveStreamProbeCapture(@"application-did-enter-background", 0.0); }];
            [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEActiveStreamProbeCapture(@"application-will-enter-foreground", 0.0); }];
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                CEActiveStreamProbeCapture(@"application-did-become-active", 0.0);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEActiveStreamProbeCapture(@"foreground-plus-0.35s", 0.25); });
            }];
            CERecoveryDiagnosticLog(@"INPLACE30-LIFECYCLE", @"installed automatic background/foreground final-stream capture");
        });
    }
}