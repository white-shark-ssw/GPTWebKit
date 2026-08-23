#import <UIKit/UIKit.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"
#import "../Network/CENetworkObserver.h"

static __weak UIView *CEGeoLastTouchedView = nil;
static NSDate *CEGeoLastTouchDate = nil;

static UIView *CEGeoRowView(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"LiftPreviewLabelMarkingView"]) return cursor;
        if ([name containsString:@"HostingScrollView"]) break;
    }
    return nil;
}

static UIView *CEGeoGroupView(UIView *row) {
    for (UIView *cursor = row.superview; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"PlatformGroupContainer"]) return cursor;
        if ([cursor isKindOfClass:UIScrollView.class]) break;
    }
    return row.superview;
}

static UIScrollView *CEGeoScrollView(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) if ([cursor isKindOfClass:UIScrollView.class]) return (UIScrollView *)cursor;
    return nil;
}

static void CEGeoCollectRows(UIView *view, Class rowClass, NSUInteger depth, NSMutableArray<UIView *> *out) {
    if (!view || depth > 4 || out.count >= 500) return;
    if ([view isKindOfClass:rowClass] || [NSStringFromClass(view.class) containsString:@"LiftPreviewLabelMarkingView"]) [out addObject:view];
    for (UIView *child in view.subviews) CEGeoCollectRows(child, rowClass, depth + 1, out);
}

static NSString *CEGeoProjectID(void) {
    NSString *path = [CENetworkObserver shared].requestTemplate.URL.path ?: @"";
    static NSRegularExpression *re; static dispatch_once_t once;
    dispatch_once(&once, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"/gizmos/(g-p-[^/]+)/conversations" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *match = [re firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (match.numberOfRanges > 1) return [path substringWithRange:[match rangeAtIndex:1]];
    NSSet<NSString *> *known = [CENetworkObserver shared].knownProjectIDs;
    return known.count == 1 ? known.anyObject : nil;
}

static NSArray<CEConversationRecord *> *CEGeoOrderedRecords(void) {
    NSDictionary *byID = nil;
    @try { byID = [[CECatalog shared] valueForKey:@"byID"]; } @catch (__unused NSException *exception) {}
    if (![byID isKindOfClass:NSDictionary.class] || !byID.count) return @[];
    NSString *projectID = CEGeoProjectID();
    NSMutableArray<CEConversationRecord *> *records = [NSMutableArray array];
    for (id value in byID.allValues) {
        if (![value isKindOfClass:CEConversationRecord.class]) continue;
        CEConversationRecord *record = value;
        if (projectID.length && ![record.projectID isEqualToString:projectID]) continue;
        if (record.conversationID.length) [records addObject:record];
    }
    if (!records.count && projectID.length) {
        for (id value in byID.allValues) if ([value isKindOfClass:CEConversationRecord.class] && ((CEConversationRecord *)value).conversationID.length) [records addObject:value];
    }
    [records sortUsingComparator:^NSComparisonResult(CEConversationRecord *a, CEConversationRecord *b) {
        NSComparisonResult time = [(b.updatedAt ?: NSDate.distantPast) compare:(a.updatedAt ?: NSDate.distantPast)];
        if (time != NSOrderedSame) return time;
        return [a.conversationID compare:b.conversationID];
    }];
    return records;
}

static NSArray<CEConversationRecord *> *CEGeoRecordsNearIndex(NSArray<CEConversationRecord *> *records, NSInteger index, NSInteger radius) {
    if (!records.count || index < 0 || index >= (NSInteger)records.count) return @[];
    if (radius <= 0) return @[records[index]];
    NSInteger start = MAX(0, index - radius), end = MIN((NSInteger)records.count - 1, index + radius);
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger i = start; i <= end; i++) [out addObject:records[i]];
    return out;
}

static NSArray<CEConversationRecord *> *CEGeoResolveFromView(UIView *sourceView) {
    if (!sourceView) return @[];
    UIView *row = CEGeoRowView(sourceView); if (!row) return @[];
    UIView *group = CEGeoGroupView(row); UIScrollView *scroll = CEGeoScrollView(row);
    NSArray<CEConversationRecord *> *records = CEGeoOrderedRecords(); if (!records.count) return @[];

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    if (group) CEGeoCollectRows(group, row.class, 0, rows);
    if (rows.count >= 2) {
        [rows sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            CGFloat ay = CGRectGetMinY([a convertRect:a.bounds toView:group]), by = CGRectGetMinY([b convertRect:b.bounds toView:group]);
            if (ay < by) return NSOrderedAscending; if (ay > by) return NSOrderedDescending; return NSOrderedSame;
        }];
        NSInteger localIndex = [rows indexOfObjectIdenticalTo:row];
        if (localIndex != NSNotFound && rows.count == records.count) return CEGeoRecordsNearIndex(records, localIndex, 0);
    }

    if (!group || !scroll) return @[];
    CGRect rowRect = [row convertRect:row.bounds toView:scroll];
    CGRect groupRect = [group convertRect:group.bounds toView:scroll];
    CGFloat rowHeight = CGRectGetHeight(rowRect);
    if (rowHeight < 30 || rowHeight > 120) return @[];
    CGFloat rowContentMidY = CGRectGetMidY(rowRect) + scroll.contentOffset.y;
    CGFloat groupContentTop = CGRectGetMinY(groupRect) + scroll.contentOffset.y;
    CGFloat rawIndex = (rowContentMidY - groupContentTop) / rowHeight - 0.5;
    NSInteger index = (NSInteger)llround(rawIndex);
    if (index < 0 || index >= (NSInteger)records.count) return @[];
    CGFloat residual = fabs(rawIndex - index);
    if (residual <= 0.12) return CEGeoRecordsNearIndex(records, index, 0);
    return CEGeoRecordsNearIndex(records, index, 2);
}

static NSArray<CEConversationRecord *> *CEGeoFreshCandidates(void) {
    if (!CEGeoLastTouchedView || !CEGeoLastTouchDate || [[NSDate date] timeIntervalSinceDate:CEGeoLastTouchDate] > 20.0) return @[];
    return CEGeoResolveFromView(CEGeoLastTouchedView);
}

@implementation UIWindow (ChatGPTEnhancerGeometryResolver)
- (void)cegeo_sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CGPoint point = [touch locationInView:self]; UIView *hit = [self hitTest:point withEvent:event];
        if (hit) { CEGeoLastTouchedView = hit; CEGeoLastTouchDate = [NSDate date]; }
    }
    [self cegeo_sendEvent:event];
}
@end

@implementation CEFeatures (ChatGPTEnhancerGeometryResolver)
+ (void)cegeo_exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu {
    NSArray<CEConversationRecord *> *resolved = candidates.count ? candidates : CEGeoFreshCandidates();
    [self cegeo_exportCandidates:resolved fromContextMenu:fromContextMenu];
}
+ (void)cegeo_renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView {
    NSArray<CEConversationRecord *> *resolved = candidates.count ? candidates : CEGeoResolveFromView(sourceView ?: CEGeoLastTouchedView);
    [self cegeo_renameCandidates:resolved sourceView:sourceView];
}
@end

__attribute__((constructor)) static void CEInstallGeometryResolver(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(cegeo_sendEvent:));
        CESwizzleClassMethod(CEFeatures.class, @selector(exportCandidates:fromContextMenu:), @selector(cegeo_exportCandidates:fromContextMenu:));
        CESwizzleClassMethod(CEFeatures.class, @selector(renameCandidates:sourceView:), @selector(cegeo_renameCandidates:sourceView:));
    }
}
