#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"

static NSArray<CEConversationRecord *> *CEAXLastCandidates = nil;
static NSString *CEAXLastTitle = nil;
static NSDate *CEAXLastResolvedAt = nil;

static NSString *CEAXQuotedConversationTitle(NSString *text) {
    if (!text.length) return nil;
    NSArray<NSArray<NSString *> *> *pairs = @[
        @[@"给“", @"”发送消息"], @[@"给\"", @"\"发送消息"], @[@"给「", @"」发送消息"],
        @[@"Message “", @"”"], @[@"Message \"", @"\""]
    ];
    for (NSArray<NSString *> *pair in pairs) {
        NSRange start = [text rangeOfString:pair[0]]; if (start.location == NSNotFound) continue;
        NSUInteger bodyStart = NSMaxRange(start);
        NSRange end = [text rangeOfString:pair[1] options:0 range:NSMakeRange(bodyStart, text.length - bodyStart)];
        if (end.location == NSNotFound || end.location <= bodyStart) continue;
        NSString *title = [[text substringWithRange:NSMakeRange(bodyStart, end.location - bodyStart)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (title.length >= 2 && title.length <= 180) return title;
    }
    return nil;
}

static NSString *CEAXCatalogTitleFromText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trim.length < 2 || trim.length > 320) return nil;
    if ([[CECatalog shared] recordsMatchingTitle:trim].count) return trim;

    NSString *quoted = CEAXQuotedConversationTitle(trim);
    if (quoted.length && [[CECatalog shared] recordsMatchingTitle:quoted].count) return quoted;

    NSArray<NSString *> *suffixes = @[@"，按钮", @", button", @" 按钮", @" button"];
    for (NSString *suffix in suffixes) {
        if (![trim.lowercaseString hasSuffix:suffix.lowercaseString] || trim.length <= suffix.length) continue;
        NSString *candidate = [[trim substringToIndex:trim.length - suffix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (candidate.length && [[CECatalog shared] recordsMatchingTitle:candidate].count) return candidate;
    }

    for (NSString *line in [trim componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *candidate = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (candidate.length >= 2 && [[CECatalog shared] recordsMatchingTitle:candidate].count) return candidate;
    }
    return nil;
}

static BOOL CEAXFrameNearPoint(CGRect frame, CGPoint point, CGFloat *distanceOut) {
    if (CGRectIsNull(frame) || CGRectIsInfinite(frame) || CGRectIsEmpty(frame)) return NO;
    CGFloat dx = 0, dy = 0;
    if (point.x < CGRectGetMinX(frame)) dx = CGRectGetMinX(frame) - point.x;
    else if (point.x > CGRectGetMaxX(frame)) dx = point.x - CGRectGetMaxX(frame);
    if (point.y < CGRectGetMinY(frame)) dy = CGRectGetMinY(frame) - point.y;
    else if (point.y > CGRectGetMaxY(frame)) dy = point.y - CGRectGetMaxY(frame);
    CGFloat distance = hypot(dx, dy); if (distanceOut) *distanceOut = distance;
    return CGRectContainsPoint(CGRectInset(frame, -18, -10), point) || distance <= 18;
}

static void CEAXConsiderObject(id object, CGPoint screenPoint, NSString **bestTitle, CGFloat *bestScore) {
    if (!object) return;
    CGRect frame = CGRectNull;
    @try { if ([object respondsToSelector:@selector(accessibilityFrame)]) frame = [object accessibilityFrame]; } @catch (__unused NSException *exception) {}
    CGFloat distance = 0; if (!CEAXFrameNearPoint(frame, screenPoint, &distance)) return;

    NSString *identifier = nil, *label = nil, *value = nil, *hint = nil;
    @try {
        if ([object respondsToSelector:@selector(accessibilityIdentifier)]) identifier = [object accessibilityIdentifier];
        if ([object respondsToSelector:@selector(accessibilityLabel)]) label = [object accessibilityLabel];
        if ([object respondsToSelector:@selector(accessibilityValue)]) value = [object accessibilityValue];
        if ([object respondsToSelector:@selector(accessibilityHint)]) hint = [object accessibilityHint];
    } @catch (__unused NSException *exception) {}

    for (NSString *text in @[label ?: @"", value ?: @"", identifier ?: @"", hint ?: @""]) {
        NSString *title = CEAXCatalogTitleFromText(text); if (!title.length) continue;
        CGFloat area = MAX(frame.size.width * frame.size.height, 1.0);
        CGFloat score = CGRectContainsPoint(frame, screenPoint) ? 1000000.0 - MIN(area, 800000.0) : 5000.0 - distance * 100.0;
        if (!*bestTitle || score > *bestScore) { *bestTitle = title; *bestScore = score; }
    }
}

static void CEAXEnumerateAccessibilityObject(id object, CGPoint screenPoint, NSUInteger depth, NSMutableSet<NSValue *> *visited, NSString **bestTitle, CGFloat *bestScore) {
    if (!object || depth > 4 || visited.count >= 2400) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)object]; if ([visited containsObject:key]) return; [visited addObject:key];
    CEAXConsiderObject(object, screenPoint, bestTitle, bestScore);

    NSArray *elements = nil;
    @try { if ([object respondsToSelector:@selector(accessibilityElements)]) elements = [object accessibilityElements]; } @catch (__unused NSException *exception) {}
    if ([elements isKindOfClass:NSArray.class]) for (id child in elements) CEAXEnumerateAccessibilityObject(child, screenPoint, depth + 1, visited, bestTitle, bestScore);

    if ([object respondsToSelector:@selector(accessibilityElementCount)] && [object respondsToSelector:@selector(accessibilityElementAtIndex:)]) {
        NSInteger count = 0;
        @try { count = [object accessibilityElementCount]; } @catch (__unused NSException *exception) { count = 0; }
        if (count > 0 && count <= 2000) {
            for (NSInteger i = 0; i < count && visited.count < 2400; i++) {
                id child = nil; @try { child = [object accessibilityElementAtIndex:i]; } @catch (__unused NSException *exception) {}
                if (child) CEAXEnumerateAccessibilityObject(child, screenPoint, depth + 1, visited, bestTitle, bestScore);
            }
        }
    }
}

static void CEAXEnumerateViewTree(UIView *view, CGPoint screenPoint, NSUInteger depth, NSMutableSet<NSValue *> *visited, NSString **bestTitle, CGFloat *bestScore) {
    if (!view || depth > 16 || view.hidden || view.alpha < 0.01 || visited.count >= 2400) return;
    CEAXEnumerateAccessibilityObject(view, screenPoint, 0, visited, bestTitle, bestScore);
    for (UIView *child in view.subviews) CEAXEnumerateViewTree(child, screenPoint, depth + 1, visited, bestTitle, bestScore);
}

static BOOL CEAXLooksLikeHistoryTouch(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"HostingScrollView"]) return YES;
        if ([name containsString:@"ChatCollectionView"] || [name containsString:@"MessagesCollection"]) return NO;
    }
    return NO;
}

static void CEAXResolveAtPoint(UIWindow *window, CGPoint point, UIView *hitView) {
    CEAXLastCandidates = nil; CEAXLastTitle = nil; CEAXLastResolvedAt = nil;
    if (!window || !hitView || !CEAXLooksLikeHistoryTouch(hitView)) return;
    CGPoint screenPoint = [window convertPoint:point toWindow:nil];
    NSString *bestTitle = nil; CGFloat bestScore = -CGFLOAT_MAX;
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    CEAXEnumerateViewTree(window, screenPoint, 0, visited, &bestTitle, &bestScore);
    if (!bestTitle.length) return;
    NSArray<CEConversationRecord *> *matches = [[CECatalog shared] recordsMatchingTitle:bestTitle];
    if (!matches.count) return;
    CEAXLastTitle = bestTitle; CEAXLastCandidates = matches; CEAXLastResolvedAt = [NSDate date];
}

static NSArray<CEConversationRecord *> *CEAXFreshCandidates(void) {
    if (!CEAXLastCandidates.count || !CEAXLastResolvedAt || [[NSDate date] timeIntervalSinceDate:CEAXLastResolvedAt] > 12.0) return @[];
    return CEAXLastCandidates;
}

@implementation UIWindow (ChatGPTEnhancerAXResolver)
- (void)ceax_sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CGPoint point = [touch locationInView:self]; UIView *hit = [self hitTest:point withEvent:event];
        if (hit) CEAXResolveAtPoint(self, point, hit);
    }
    [self ceax_sendEvent:event];
}
@end

@implementation CEFeatures (ChatGPTEnhancerAXResolver)
+ (void)ceax_exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu {
    NSArray<CEConversationRecord *> *resolved = candidates.count ? candidates : CEAXFreshCandidates();
    [self ceax_exportCandidates:resolved fromContextMenu:fromContextMenu];
}
+ (void)ceax_renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView {
    NSArray<CEConversationRecord *> *resolved = candidates.count ? candidates : CEAXFreshCandidates();
    [self ceax_renameCandidates:resolved sourceView:sourceView];
}
@end

__attribute__((constructor)) static void CEInstallAccessibilityResolver(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(ceax_sendEvent:));
        CESwizzleClassMethod(CEFeatures.class, @selector(exportCandidates:fromContextMenu:), @selector(ceax_exportCandidates:fromContextMenu:));
        CESwizzleClassMethod(CEFeatures.class, @selector(renameCandidates:sourceView:), @selector(ceax_renameCandidates:sourceView:));
    }
}
