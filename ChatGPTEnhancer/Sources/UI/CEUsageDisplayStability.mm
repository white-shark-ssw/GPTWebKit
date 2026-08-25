#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"

static NSMutableDictionary<NSString *, NSString *> *CEUsage38Cache;

static NSString *CEUsage38CachedText(NSString *conversationID) {
    if (!conversationID.length) return nil;
    @synchronized (CEUsage38Cache) { return [CEUsage38Cache[conversationID] copy]; }
}

static void CEUsage38StoreText(NSString *conversationID, NSString *text) {
    if (!conversationID.length || !text.length) return;
    @synchronized (CEUsage38Cache) { CEUsage38Cache[conversationID] = [text copy]; }
}

static UIButton *CEUsage38ExistingFloatingButton(void) {
    Class cls = NSClassFromString(@"CEFloatingButtonController"); SEL sharedSEL = NSSelectorFromString(@"shared");
    if (!cls || ![cls respondsToSelector:sharedSEL]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSEL); if (!controller) return nil;
    Ivar ivar = class_getInstanceVariable(cls, "_button"); if (!ivar) return nil;
    id button = object_getIvar(controller, ivar); return [button isKindOfClass:UIButton.class] ? button : nil;
}

static BOOL CEUsage38ValidPercentText(NSString *text) {
    if (text.length < 2 || ![text hasSuffix:@"%"] || [text isEqualToString:@"--%"]) return NO;
    NSString *digits = [text substringToIndex:text.length - 1];
    NSCharacterSet *notDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet; if ([digits rangeOfCharacterFromSet:notDigits].location != NSNotFound) return NO;
    NSInteger value = digits.integerValue; return value >= 0 && value <= 99;
}

@interface UIButton (CEUsageDisplayStability)
- (void)ce_usage38_setTitle:(NSString *)title forState:(UIControlState)state;
@end

@implementation UIButton (CEUsageDisplayStability)
- (void)ce_usage38_setTitle:(NSString *)title forState:(UIControlState)state {
    UIButton *floating = CEUsage38ExistingFloatingButton();
    if (self == floating && state == UIControlStateNormal && CEUsage38ValidPercentText(title)) {
        NSString *conversationID = [CEConversationContext shared].conversationID;
        CEUsage38StoreText(conversationID, title);
    }
    [self ce_usage38_setTitle:title forState:state];
}
@end

static void CEUsage38RestoreCurrent(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *conversationID = [CEConversationContext shared].conversationID; NSString *cached = CEUsage38CachedText(conversationID); UIButton *button = CEUsage38ExistingFloatingButton();
        if (!conversationID.length || !cached.length || !button) return;
        NSString *current = [button titleForState:UIControlStateNormal];
        if (!current.length) {
            [button setTitle:cached forState:UIControlStateNormal];
            CERecoveryDiagnosticLog(@"USAGE38", @"restored in-process percentage after button recreation conversation=%@ cached=%@", conversationID, cached);
        }
    });
}

__attribute__((constructor)) static void CEUsageDisplayStabilityEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        static dispatch_once_t once; dispatch_once(&once, ^{
            CEUsage38Cache = [NSMutableDictionary dictionary];
            CESwizzleInstanceMethod(UIButton.class, @selector(setTitle:forState:), @selector(ce_usage38_setTitle:forState:));
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:CEConversationContextDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEUsage38RestoreCurrent(); }];
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CEUsage38RestoreCurrent(); }];
            CERecoveryDiagnosticLog(@"USAGE38", @"in-process percentage display cache installed; explicit unknown is never overridden");
        });
    }
}
