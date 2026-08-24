#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Diagnostics/CEDiagnostics.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "CEOrphanedConversationRecovery.h"

static IMP CEManualReloadOriginalIMP = NULL;

static void CEManualReloadCurrentConversation(id self, SEL _cmd) {
    NSString *conversationID = [CEConversationContext shared].conversationID;
    if (!conversationID.length) { CEShowMessage(@"无法识别当前会话。"); return; }
    CECaptureFocusedActiveConversationDiagnostics(@"manual reload before exact native route");
    CERecoveryDiagnosticMark(@"MANUAL RELOAD CURRENT CONVERSATION");
    CERecoveryDiagnosticLog(@"MANUAL-RELOAD", @"requested exact current conversation=%@ appState=%ld", conversationID, (long)UIApplication.sharedApplication.applicationState);
    CEShowMessage(@"正在重载当前会话…");
    CEOrphanForceReloadConversation(conversationID, ^(BOOL success) {
        if (success) CEShowMessage(@"✓ 当前会话已重载");
        else CEShowMessage(@"重载未完成，当前页面保持不变。");
    });
}

static void CEInstallManualReloadOverride(NSUInteger attempt) {
    Class cls = NSClassFromString(@"CEFeatures");
    SEL selector = NSSelectorFromString(@"reloadCurrentConversation");
    Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    if (method) {
        IMP current = method_getImplementation(method);
        if (current != (IMP)CEManualReloadCurrentConversation) {
            CEManualReloadOriginalIMP = current;
            method_setImplementation(method, (IMP)CEManualReloadCurrentConversation);
        }
        CERecoveryDiagnosticLog(@"MANUAL-RELOAD", @"hook installed class=%@ selector=%@ originalIMP=%p", NSStringFromClass(cls), NSStringFromSelector(selector), CEManualReloadOriginalIMP);
        return;
    }
    if (attempt >= 20) { CERecoveryDiagnosticLog(@"MANUAL-RELOAD", @"hook unavailable after %lu attempts", (unsigned long)attempt); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEInstallManualReloadOverride(attempt + 1); });
}

__attribute__((constructor)) static void CEManualConversationReloadEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ CEInstallManualReloadOverride(0); });
    }
}
