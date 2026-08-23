#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Core/CECore.h"

static __weak UIView *CEDiagLastTouchedView = nil;
static NSDate *CEDiagLastTouchDate = nil;
static NSString *CEDiagContextSnapshot = nil;
static NSDate *CEDiagContextSnapshotDate = nil;

static void CEDiagAppendAccessibilityValue(NSMutableOrderedSet<NSString *> *out, id object) {
    if (!object || out.count >= 220) return;
    NSString *identifier = nil, *label = nil, *value = nil;
    @try {
        if ([object respondsToSelector:@selector(accessibilityIdentifier)]) identifier = [object accessibilityIdentifier];
        if ([object respondsToSelector:@selector(accessibilityLabel)]) label = [object accessibilityLabel];
        if ([object respondsToSelector:@selector(accessibilityValue)]) value = [object accessibilityValue];
    } @catch (__unused NSException *exception) {}
    for (NSString *text in @[identifier ?: @"", label ?: @"", value ?: @""]) {
        NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trim.length && trim.length <= 500) [out addObject:trim];
    }
}

static void CEDiagCollectAccessibility(UIView *view, NSUInteger depth, NSMutableOrderedSet<NSString *> *out) {
    if (!view || depth > 10 || out.count >= 220) return;
    CEDiagAppendAccessibilityValue(out, view);
    NSArray *elements = nil; @try { elements = view.accessibilityElements; } @catch (__unused NSException *exception) {}
    for (id element in elements ?: @[]) CEDiagAppendAccessibilityValue(out, element);
    for (UIView *child in view.subviews) CEDiagCollectAccessibility(child, depth + 1, out);
}

static NSString *CEDiagViewChain(UIView *view) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UIView *cursor = view; cursor && lines.count < 14; cursor = cursor.superview) {
        [lines addObject:[NSString stringWithFormat:@"%lu. %@ id=%@ label=%@ value=%@", (unsigned long)lines.count, NSStringFromClass(cursor.class), cursor.accessibilityIdentifier ?: @"", cursor.accessibilityLabel ?: @"", cursor.accessibilityValue ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *CEDiagBuildContextSnapshot(NSString *identifierText) {
    UIWindow *window = CEKeyWindow();
    UIView *source = nil;
    if (CEDiagLastTouchedView && CEDiagLastTouchDate && [[NSDate date] timeIntervalSinceDate:CEDiagLastTouchDate] <= 8.0) source = CEDiagLastTouchedView;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"[Pre-menu snapshot]\ncontextMenuIdentifier=%@\nsourceClass=%@\n", identifierText.length ? identifierText : @"<nil>", source ? NSStringFromClass(source.class) : @"<nil>"];
    [out appendFormat:@"sourceViewChain:\n%@\n", source ? CEDiagViewChain(source) : @"<nil>"];

    NSMutableOrderedSet<NSString *> *sourceAccessibility = [NSMutableOrderedSet orderedSet];
    if (source) CEDiagCollectAccessibility(source, 0, sourceAccessibility);
    [out appendString:@"sourceAccessibility:\n"];
    NSUInteger sourceACount = MIN((NSUInteger)80, sourceAccessibility.count);
    for (NSUInteger i = 0; i < sourceACount; i++) [out appendFormat:@"SA%03lu: %@\n", (unsigned long)i, sourceAccessibility[i]];

    NSArray<NSString *> *sourceVisible = source ? CECollectVisibleStrings(source, 7) : @[];
    [out appendString:@"sourceVisible:\n"];
    NSUInteger sourceVCount = MIN((NSUInteger)80, sourceVisible.count);
    for (NSUInteger i = 0; i < sourceVCount; i++) [out appendFormat:@"SV%03lu: %@\n", (unsigned long)i, sourceVisible[i]];

    NSMutableOrderedSet<NSString *> *windowAccessibility = [NSMutableOrderedSet orderedSet];
    if (window) CEDiagCollectAccessibility(window, 0, windowAccessibility);
    [out appendString:@"windowAccessibility:\n"];
    NSUInteger windowACount = MIN((NSUInteger)80, windowAccessibility.count);
    for (NSUInteger i = 0; i < windowACount; i++) [out appendFormat:@"WA%03lu: %@\n", (unsigned long)i, windowAccessibility[i]];

    NSArray<NSString *> *windowVisible = window ? CECollectVisibleStrings(window, 10) : @[];
    [out appendString:@"windowVisible:\n"];
    NSUInteger windowVCount = MIN((NSUInteger)100, windowVisible.count);
    for (NSUInteger i = 0; i < windowVCount; i++) [out appendFormat:@"WV%03lu: %@\n", (unsigned long)i, windowVisible[i]];
    return out;
}

static void CEDiagStoreContextSnapshot(id<NSCopying> identifier) {
    NSString *identifierText = [(id)identifier description];
    CEDiagContextSnapshot = [CEDiagBuildContextSnapshot(identifierText) copy];
    CEDiagContextSnapshotDate = [NSDate date];
}

static NSString *CEDiagFreshContextSnapshot(void) {
    if (!CEDiagContextSnapshot.length || !CEDiagContextSnapshotDate) return nil;
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:CEDiagContextSnapshotDate];
    if (age > 90.0) return nil;
    return [NSString stringWithFormat:@"%@snapshotAge=%.2fs\n", CEDiagContextSnapshot, age];
}

@interface UIWindow (ChatGPTEnhancerDiagnosticsSnapshot)
- (void)ce_diag_sendEvent:(UIEvent *)event;
@end

@implementation UIWindow (ChatGPTEnhancerDiagnosticsSnapshot)
- (void)ce_diag_sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CGPoint point = [touch locationInView:self];
        UIView *hit = [self hitTest:point withEvent:event];
        if (hit) { CEDiagLastTouchedView = hit; CEDiagLastTouchDate = [NSDate date]; }
    }
    [self ce_diag_sendEvent:event];
}
@end

@interface UIContextMenuConfiguration (ChatGPTEnhancerDiagnosticsSnapshot)
+ (instancetype)ce_diag_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider;
@end

@implementation UIContextMenuConfiguration (ChatGPTEnhancerDiagnosticsSnapshot)
+ (instancetype)ce_diag_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider {
    CEDiagStoreContextSnapshot(identifier);
    return [self ce_diag_configurationWithIdentifier:identifier previewProvider:previewProvider actionProvider:actionProvider];
}
@end

@interface UIAlertAction (ChatGPTEnhancerDiagnosticsSnapshot)
+ (instancetype)ce_diag_actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^ _Nullable)(UIAlertAction *action))handler;
@end

@implementation UIAlertAction (ChatGPTEnhancerDiagnosticsSnapshot)
+ (instancetype)ce_diag_actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    if (![title isEqualToString:@"复制诊断"]) return [self ce_diag_actionWithTitle:title style:style handler:handler];
    void (^wrapped)(UIAlertAction *) = ^(UIAlertAction *action) {
        if (handler) handler(action);
        NSString *snapshot = CEDiagFreshContextSnapshot();
        if (!snapshot.length) return;
        NSString *base = UIPasteboard.generalPasteboard.string ?: @"";
        if ([base containsString:@"[Pre-menu snapshot]"]) return;
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n\n%@", base, snapshot];
    };
    return [self ce_diag_actionWithTitle:title style:style handler:wrapped];
}
@end

__attribute__((constructor)) static void CEDiagnosticsSnapshotEntry(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                static dispatch_once_t once;
                dispatch_once(&once, ^{
                    CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(ce_diag_sendEvent:));
                    SEL contextFactory = @selector(configurationWithIdentifier:previewProvider:actionProvider:);
                    if ([UIContextMenuConfiguration respondsToSelector:contextFactory]) CESwizzleClassMethod(UIContextMenuConfiguration.class, contextFactory, @selector(ce_diag_configurationWithIdentifier:previewProvider:actionProvider:));
                    CESwizzleClassMethod(UIAlertAction.class, @selector(actionWithTitle:style:handler:), @selector(ce_diag_actionWithTitle:style:handler:));
                });
            });
        });
    }
}
