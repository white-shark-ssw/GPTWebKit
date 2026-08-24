#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "CEFeatures.h"
#import "../Core/CECore.h"

static const void *CEExportAbandonedKey = &CEExportAbandonedKey;

static BOOL CEExportJobAbandoned(id job) { return [objc_getAssociatedObject(job, CEExportAbandonedKey) boolValue]; }
static void CESetExportJobAbandoned(id job) { if (job) objc_setAssociatedObject(job, CEExportAbandonedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

@implementation CEFeatures (ChatGPTEnhancerExportCancellation)

+ (void)cecancel_showProgressForJob:(id)job {
    [self cecancel_showProgressForJob:job];
    if (!job || CEExportJobAbandoned(job)) return;
    UIAlertController *progress = nil;
    @try { progress = [job valueForKey:@"progressAlert"]; } @catch (__unused NSException *exception) {}
    if (![progress isKindOfClass:UIAlertController.class]) return;
    for (UIAlertAction *action in progress.actions) if ([action.title isEqualToString:@"关闭"]) return;
    __weak UIAlertController *weakProgress = progress;
    [progress addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        CESetExportJobAbandoned(job);
        UIAlertController *alert = weakProgress;
        if (alert.presentingViewController) [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
}

+ (void)cecancel_finishExportJob:(id)job {
    if (CEExportJobAbandoned(job)) { NSLog(@"[ChatGPTEnhancer] markdown export result ignored after user closed progress"); return; }
    [self cecancel_finishExportJob:job];
}

@end

__attribute__((constructor)) static void CEInstallExportCancellation(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                Class cls = CEFeatures.class;
                SEL show = NSSelectorFromString(@"showProgressForJob:");
                SEL finish = NSSelectorFromString(@"finishExportJob:");
                if ([cls respondsToSelector:show]) CESwizzleClassMethod(cls, show, @selector(cecancel_showProgressForJob:));
                if ([cls respondsToSelector:finish]) CESwizzleClassMethod(cls, finish, @selector(cecancel_finishExportJob:));
                NSLog(@"[ChatGPTEnhancer] markdown export close control installed");
            });
        });
    }
}
