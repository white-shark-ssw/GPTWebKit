#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"

static IMP CEConversationToolsOriginalButtonTappedIMP = NULL;

static CEConversationRecord *CEConversationToolsCurrentRecord(void) {
    NSString *conversationID = [CEConversationContext shared].conversationID;
    if (!conversationID.length) return nil;
    CEConversationRecord *record = [[CECatalog shared] recordForID:conversationID];
    if (record) return record;
    record = [CEConversationRecord new];
    record.conversationID = conversationID;
    record.title = [CEConversationContext shared].title.length ? [CEConversationContext shared].title : @"当前会话";
    return record;
}

static UIView *CEConversationToolsSourceView(id controller, UIViewController *presenter) {
    UIView *button = nil;
    @try { button = [controller valueForKey:@"button"]; } @catch (__unused NSException *exception) {}
    return button ?: presenter.view;
}

static void CEConversationToolsButtonTapped(id self, SEL _cmd) {
    CEConversationRecord *record = CEConversationToolsCurrentRecord();
    if (!record.conversationID.length) return;
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"会话工具" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"拉取最新消息" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [CEFeatures pullLatestCurrentConversation]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重载当前会话" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [CEFeatures reloadCurrentConversation]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出 MD 文档" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [CEFeatures exportRecord:record requireConfirmation:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIView *sourceView = CEConversationToolsSourceView(self, vc);
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    CERecoveryDiagnosticLog(@"TOOLS-MENU", @"presented production menu conversation=%@ actions=pull,reload,export diagnosticsHidden=YES", record.conversationID);
    [vc presentViewController:sheet animated:YES completion:nil];
}

static void CEInstallConversationToolsMenuOverride(NSUInteger attempt) {
    Class cls = NSClassFromString(@"CEFloatingButtonController");
    SEL selector = NSSelectorFromString(@"buttonTapped");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (method) {
        IMP current = method_getImplementation(method);
        if (current != (IMP)CEConversationToolsButtonTapped) {
            CEConversationToolsOriginalButtonTappedIMP = current;
            method_setImplementation(method, (IMP)CEConversationToolsButtonTapped);
        }
        CERecoveryDiagnosticLog(@"TOOLS-MENU", @"hook installed class=%@ selector=%@ originalIMP=%p", NSStringFromClass(cls), NSStringFromSelector(selector), CEConversationToolsOriginalButtonTappedIMP);
        return;
    }
    if (attempt >= 20) { CERecoveryDiagnosticLog(@"TOOLS-MENU", @"hook unavailable after %lu attempts", (unsigned long)attempt); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEInstallConversationToolsMenuOverride(attempt + 1); });
}

__attribute__((constructor)) static void CEConversationToolsMenuEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ CEInstallConversationToolsMenuOverride(0); });
    }
}
