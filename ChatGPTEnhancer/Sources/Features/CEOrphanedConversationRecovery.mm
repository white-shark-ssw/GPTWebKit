#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <string.h>
#import <math.h>
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"
#import "CEOrphanedConversationRecovery.h"

static NSDate *CEOrphanBackgroundDate = nil;
static NSDate *CEOrphanForegroundDate = nil;
static NSString *CEOrphanBackgroundConversationID = nil;
static BOOL CEOrphanHadStreamAtBackground = NO;
static NSUInteger CEOrphanGeneration = 0;
static NSUInteger CEOrphanContextGeneration = 0;
static NSDate *CEOrphanLastReselectAt = nil;
static NSUInteger CEOrphanManualReloadGeneration = 0;
static NSUInteger CEOrphanHistorySelectionGeneration = 0;
static IMP CEOrphanOriginalHistoryDidSelectIMP = NULL;
static BOOL CEOrphanHistorySelectionHookInstalled = NO;
static id CEOrphanConfirmedHistoryIdentifier = nil;
static NSIndexPath *CEOrphanConfirmedHistoryIndexPath = nil;
static NSString *CEOrphanConfirmedHistoryConversationID = nil;

static BOOL CEOrphanConversationFinished(NSData *data) {
    if (!data.length) return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *root = (NSDictionary *)json;
    NSString *currentNode = [root[@"current_node"] isKindOfClass:NSString.class] ? root[@"current_node"] : nil;
    NSDictionary *mapping = [root[@"mapping"] isKindOfClass:NSDictionary.class] ? root[@"mapping"] : nil;
    NSDictionary *node = currentNode.length && mapping && [mapping[currentNode] isKindOfClass:NSDictionary.class] ? mapping[currentNode] : nil;
    NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
    NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : nil;
    NSString *role = [author[@"role"] isKindOfClass:NSString.class] ? [author[@"role"] lowercaseString] : @"";
    NSString *status = [message[@"status"] isKindOfClass:NSString.class] ? [message[@"status"] lowercaseString] : @"";
    NSNumber *endTurn = [message[@"end_turn"] isKindOfClass:NSNumber.class] ? message[@"end_turn"] : nil;
    if (![role isEqualToString:@"assistant"]) return NO;
    if (endTurn.boolValue) return YES;
    return [status containsString:@"finished"] || [status containsString:@"complete"] || [status containsString:@"success"] || [status isEqualToString:@"done"];
}

static BOOL CEOrphanLooksLikeConversationStream(NSURLRequest *request) {
    if (!request.URL) return NO;
    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";
    NSString *path = request.URL.path.lowercaseString ?: @"";
    if (![method isEqualToString:@"POST"] || ![path containsString:@"conversation"]) return NO;
    NSArray<NSString *> *excluded = @[@"/prepare", @"/init", @"gen_title", @"feedback", @"share", @"search", @"message_feedback", @"conversation_limit"];
    for (NSString *token in excluded) if ([path containsString:token]) return NO;
    NSString *accept = [[request valueForHTTPHeaderField:@"Accept"] lowercaseString] ?: @"";
    if ([accept containsString:@"text/event-stream"]) return YES;
    if ([path hasSuffix:@"/backend-api/conversation"] || [path hasSuffix:@"/backend-api/f/conversation"]) return YES;
    return [path containsString:@"/conversation/stream"] || [path containsString:@"/f/conversation/"];
}

static BOOL CEOrphanRecentOfficialConversationActivitySince(NSDate *date) {
    if (!date) return NO;
    long long threshold = (long long)(date.timeIntervalSince1970 * 1000.0);
    for (NSString *event in [CENetworkObserver shared].recentEvents.reverseObjectEnumerator) {
        long long timestamp = event.longLongValue; if (timestamp && timestamp < threshold) break;
        NSString *lower = event.lowercaseString;
        if (![lower containsString:@" req "] || [lower containsString:@"/prepare"] || [lower containsString:@"/init"]) continue;
        if ([lower containsString:@"/backend-api/conversation/"] || [lower containsString:@"post /backend-api/conversation "] || [lower containsString:@"post /backend-api/f/conversation "] || [lower containsString:@"/conversation/stream"]) return YES;
    }
    return NO;
}

static BOOL CEOrphanViewHasCentralLoader(UIView *view, UIWindow *window, NSUInteger depth) {
    if (!view || !window || depth > 18 || view.hidden || view.alpha < 0.02 || !view.window) return NO;
    NSString *className = NSStringFromClass(view.class).lowercaseString;
    BOOL loaderClass = [view isKindOfClass:UIActivityIndicatorView.class] || [className containsString:@"activityindicator"] || [className containsString:@"spinner"];
    if (loaderClass) {
        if ([view isKindOfClass:UIActivityIndicatorView.class] && !((UIActivityIndicatorView *)view).isAnimating) loaderClass = NO;
        if (loaderClass) {
            CGRect frame = [view convertRect:view.bounds toView:window];
            CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
            CGFloat width = CGRectGetWidth(window.bounds), height = CGRectGetHeight(window.bounds);
            if (CGRectGetWidth(frame) <= 120 && CGRectGetHeight(frame) <= 120 && center.x >= width * 0.20 && center.x <= width * 0.80 && center.y >= height * 0.22 && center.y <= height * 0.78) return YES;
        }
    }
    for (UIView *child in view.subviews) if (CEOrphanViewHasCentralLoader(child, window, depth + 1)) return YES;
    return NO;
}

static BOOL CEOrphanHasCentralLoadingIndicator(void) {
    UIViewController *top = CETopViewController();
    if ([top isKindOfClass:UIAlertController.class] || [top isKindOfClass:UIDocumentPickerViewController.class]) return NO;
    UIWindow *window = CEKeyWindow();
    return window ? CEOrphanViewHasCentralLoader(window, window, 0) : NO;
}

static BOOL CEOrphanMallocInfo(const void *pointer, size_t *sizeOut) {
    if (!pointer) return NO;
    uintptr_t raw = (uintptr_t)pointer; if (raw < 0x100000000ULL || (raw & 0x7ULL) != 0) return NO;
    malloc_zone_t *zone = malloc_zone_from_ptr(pointer); if (!zone) return NO;
    size_t size = malloc_size(pointer); if (size < 16 || size > 1024 * 1024) return NO;
    if (sizeOut) *sizeOut = size;
    return YES;
}

static BOOL CEOrphanBytesContainID(const uint8_t *bytes, size_t length, const uint8_t *needle, size_t needleLength) {
    if (!bytes || !needle || !needleLength || length < needleLength) return NO;
    size_t offset = 0;
    while (offset + needleLength <= length) {
        const void *hit = memchr(bytes + offset, needle[0], length - offset - needleLength + 1); if (!hit) return NO;
        size_t index = (const uint8_t *)hit - bytes; if (memcmp(bytes + index, needle, needleLength) == 0) return YES; offset = index + 1;
    }
    return NO;
}

static BOOL CEOrphanScanPointerForID(const void *pointer, const uint8_t *needle, size_t needleLength, NSUInteger depth, NSMutableSet<NSValue *> *visited, NSUInteger *allocations, NSUInteger *bytes) {
    if (!pointer || depth > 5 || visited.count >= 64 || *allocations >= 64 || *bytes >= 160 * 1024) return NO;
    size_t allocationSize = 0; if (!CEOrphanMallocInfo(pointer, &allocationSize)) return NO;
    NSValue *key = [NSValue valueWithPointer:pointer]; if ([visited containsObject:key]) return NO; [visited addObject:key]; (*allocations)++;
    size_t scanLength = MIN(allocationSize, (size_t)6144); size_t remaining = 160 * 1024 - *bytes; scanLength = MIN(scanLength, remaining); *bytes += scanLength;
    if (CEOrphanBytesContainID((const uint8_t *)pointer, scanLength, needle, needleLength)) return YES;
    size_t pointerBytes = MIN(scanLength, (size_t)1024);
    for (size_t offset = 0; offset + sizeof(void *) <= pointerBytes; offset += sizeof(void *)) {
        uintptr_t raw = 0; memcpy(&raw, (const uint8_t *)pointer + offset, sizeof(raw)); if (!raw || (raw & 0x7ULL) != 0 || raw == (uintptr_t)pointer) continue;
        const void *child = (const void *)raw; size_t childSize = 0; if (!CEOrphanMallocInfo(child, &childSize)) continue;
        if (CEOrphanScanPointerForID(child, needle, needleLength, depth + 1, visited, allocations, bytes)) return YES;
    }
    return NO;
}

static BOOL CEOrphanObjectContainsConversationID(id object, NSString *conversationID) {
    if (!object || !conversationID.length) return NO;
    NSString *description = nil; @try { description = [object description]; } @catch (__unused NSException *exception) {}
    if ([description containsString:conversationID]) return YES;
    NSData *utf8 = [conversationID dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set]; NSUInteger allocations = 0, bytes = 0;
    return utf8.length && CEOrphanScanPointerForID((__bridge const void *)object, (const uint8_t *)utf8.bytes, utf8.length, 0, visited, &allocations, &bytes);
}

static BOOL CEOrphanRecentDetailRequestForConversationSince(NSString *conversationID, NSDate *date) {
    if (!conversationID.length || !date) return NO;
    long long threshold = (long long)(date.timeIntervalSince1970 * 1000.0);
    NSString *cid = conversationID.lowercaseString;
    for (NSString *event in [CENetworkObserver shared].recentEvents.reverseObjectEnumerator) {
        long long timestamp = event.longLongValue; if (timestamp && timestamp < threshold) break;
        NSString *lower = event.lowercaseString;
        if (![lower containsString:@" req "]) continue;
        if ([lower containsString:[NSString stringWithFormat:@"/backend-api/conversation/%@", cid]] || [lower containsString:[NSString stringWithFormat:@"/backend-api/f/conversation/%@", cid]]) return YES;
    }
    return NO;
}

static id CEOrphanHistoryItemIdentifier(UICollectionView *collection, NSIndexPath *indexPath) {
    id dataSource = collection.dataSource; SEL selector = NSSelectorFromString(@"itemIdentifierForIndexPath:");
    if (!collection || !indexPath || !dataSource || ![dataSource respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(dataSource, selector, indexPath);
}

static void CEOrphanConfirmHistorySelection(id identifier, NSIndexPath *indexPath, NSDate *selectedAt, NSUInteger generation) {
    if (generation != CEOrphanHistorySelectionGeneration || !identifier || !indexPath || !selectedAt) return;
    NSString *conversationID = [[CEConversationContext shared].conversationID copy];
    if (!conversationID.length || !CEOrphanRecentDetailRequestForConversationSince(conversationID, selectedAt)) return;
    CEOrphanConfirmedHistoryIdentifier = identifier;
    CEOrphanConfirmedHistoryIndexPath = [indexPath copy];
    CEOrphanConfirmedHistoryConversationID = conversationID;
    NSLog(@"[ChatGPTEnhancer] captured exact history selection for %@ section=%ld item=%ld identifierClass=%@", conversationID, (long)indexPath.section, (long)indexPath.item, NSStringFromClass([identifier class]));
}

static void CEOrphanHistoryDidSelect(id self, SEL _cmd, UICollectionView *collection, NSIndexPath *indexPath) {
    id identifier = CEOrphanHistoryItemIdentifier(collection, indexPath);
    NSDate *selectedAt = NSDate.date; NSUInteger generation = ++CEOrphanHistorySelectionGeneration;
    if (CEOrphanOriginalHistoryDidSelectIMP) ((void (*)(id, SEL, id, id))CEOrphanOriginalHistoryDidSelectIMP)(self, _cmd, collection, indexPath);
    for (NSNumber *delayValue in @[@0.20, @0.55, @1.10, @1.80]) {
        NSTimeInterval delay = delayValue.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanConfirmHistorySelection(identifier, indexPath, selectedAt, generation); });
    }
}

static void CEOrphanInstallHistorySelectionCapture(NSUInteger attempt) {
    if (CEOrphanHistorySelectionHookInstalled) return;
    Class cls = NSClassFromString(@"ChatGPTHistory.HistoryViewController");
    SEL selector = NSSelectorFromString(@"collectionView:didSelectItemAtIndexPath:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (method) {
        CEOrphanOriginalHistoryDidSelectIMP = method_getImplementation(method);
        method_setImplementation(method, (IMP)CEOrphanHistoryDidSelect);
        CEOrphanHistorySelectionHookInstalled = YES;
        NSLog(@"[ChatGPTEnhancer] exact history selection capture installed");
        return;
    }
    if (attempt >= 20) { NSLog(@"[ChatGPTEnhancer] exact history selection capture unavailable"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanInstallHistorySelectionCapture(attempt + 1); });
}

static UIViewController *CEOrphanFindHistoryController(UIViewController *vc, NSUInteger depth) {
    if (!vc || depth > 14) return nil;
    if ([NSStringFromClass(vc.class) isEqualToString:@"ChatGPTHistory.HistoryViewController"]) return vc;
    if (vc.presentedViewController) { UIViewController *found = CEOrphanFindHistoryController(vc.presentedViewController, depth + 1); if (found) return found; }
    for (UIViewController *child in vc.childViewControllers) { UIViewController *found = CEOrphanFindHistoryController(child, depth + 1); if (found) return found; }
    return nil;
}

static UICollectionView *CEOrphanFindHistoryCollection(UIView *view, NSUInteger depth) {
    if (!view || depth > 18) return nil;
    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection = (UICollectionView *)view; NSString *dataSourceClass = collection.dataSource ? NSStringFromClass([(id)collection.dataSource class]) : @"";
        if ([dataSourceClass containsString:@"ChatGPTHistory"] || [dataSourceClass containsString:@"UICollectionViewDiffableDataSource"]) return collection;
    }
    for (UIView *child in view.subviews) { UICollectionView *found = CEOrphanFindHistoryCollection(child, depth + 1); if (found) return found; }
    return nil;
}

static BOOL CEOrphanReselectConversationInternal(NSString *conversationID, BOOL bypassCooldown) {
    if (!conversationID.length || (!bypassCooldown && CEOrphanLastReselectAt && [NSDate.date timeIntervalSinceDate:CEOrphanLastReselectAt] < 20.0)) return NO;
    UIWindow *window = CEKeyWindow(); UIViewController *history = CEOrphanFindHistoryController(window.rootViewController, 0);
    UICollectionView *collection = history ? CEOrphanFindHistoryCollection(history.viewIfLoaded, 0) : nil;
    id dataSource = collection.dataSource; SEL itemSelector = NSSelectorFromString(@"itemIdentifierForIndexPath:"); SEL selectSelector = NSSelectorFromString(@"collectionView:didSelectItemAtIndexPath:");
    if (!history || !collection || !dataSource || ![dataSource respondsToSelector:itemSelector] || ![history respondsToSelector:selectSelector]) {
        NSLog(@"[ChatGPTEnhancer] orphan recovery could not access history diffable data source"); return NO;
    }
    NSMutableArray<NSIndexPath *> *matches = [NSMutableArray array]; NSUInteger inspected = 0;
    NSInteger sections = collection.numberOfSections;
    for (NSInteger section = 0; section < sections && inspected < 180; section++) {
        NSInteger items = [collection numberOfItemsInSection:section];
        for (NSInteger item = 0; item < items && inspected < 180; item++, inspected++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
            id identifier = ((id (*)(id, SEL, id))objc_msgSend)(dataSource, itemSelector, indexPath);
            if (CEOrphanObjectContainsConversationID(identifier, conversationID)) [matches addObject:indexPath];
        }
    }
    NSIndexPath *target = matches.firstObject;
    if (!target) { NSLog(@"[ChatGPTEnhancer] orphan recovery history row not found for %@ inspected=%lu", conversationID, (unsigned long)inspected); return NO; }
    CEOrphanLastReselectAt = NSDate.date;
    [collection selectItemAtIndexPath:target animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    ((void (*)(id, SEL, id, id))objc_msgSend)(history, selectSelector, collection, target);
    NSLog(@"[ChatGPTEnhancer] orphan recovery reselected %@ at section=%ld item=%ld matches=%lu", conversationID, (long)target.section, (long)target.item, (unsigned long)matches.count);
    return YES;
}

BOOL CEOrphanReselectConversation(NSString *conversationID) { return CEOrphanReselectConversationInternal(conversationID, NO); }

static BOOL CEOrphanIsSidebarControlCandidate(UIView *view, UIWindow *window, CGFloat *scoreOut) {
    if (!view || !window || view.hidden || view.alpha < 0.05 || !view.userInteractionEnabled || !view.window) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGFloat safeTop = window.safeAreaInsets.top;
    if (CGRectIsEmpty(frame) || CGRectGetMaxX(frame) < 8 || CGRectGetMinX(frame) > MIN(125.0, CGRectGetWidth(window.bounds) * 0.32)) return NO;
    if (CGRectGetMidY(frame) < safeTop - 8 || CGRectGetMidY(frame) > safeTop + 92) return NO;
    if (CGRectGetWidth(frame) < 18 || CGRectGetHeight(frame) < 18 || CGRectGetWidth(frame) > 130 || CGRectGetHeight(frame) > 110) return NO;

    BOOL control = [view isKindOfClass:UIControl.class];
    BOOL buttonTrait = (view.accessibilityTraits & UIAccessibilityTraitButton) != 0;
    BOOL gesture = view.gestureRecognizers.count > 0;
    if (!control && !buttonTrait && !gesture) return NO;

    NSString *label = [NSString stringWithFormat:@"%@ %@ %@ %@", view.accessibilityLabel ?: @"", view.accessibilityIdentifier ?: @"", view.accessibilityValue ?: @"", NSStringFromClass(view.class)];
    NSString *lower = label.lowercaseString;
    NSArray<NSString *> *reject = @[@"关闭", @"close", @"取消", @"cancel", @"完成", @"done", @"返回", @"back"];
    for (NSString *token in reject) if ([lower containsString:token.lowercaseString]) return NO;

    CGFloat targetX = 34.0, targetY = safeTop + 26.0;
    CGFloat dx = CGRectGetMidX(frame) - targetX, dy = CGRectGetMidY(frame) - targetY;
    CGFloat score = 160.0 - hypot(dx, dy);
    if (control) score += 70.0;
    if (buttonTrait) score += 55.0;
    if ([lower containsString:@"sidebar"] || [lower containsString:@"side menu"] || [lower containsString:@"侧边"] || [lower containsString:@"菜单"] || [lower containsString:@"history"] || [lower containsString:@"历史"]) score += 260.0;
    if ([lower containsString:@"button"]) score += 30.0;
    if (scoreOut) *scoreOut = score;
    return YES;
}

static void CEOrphanFindSidebarControl(UIView *view, UIWindow *window, NSUInteger depth, UIView **best, CGFloat *bestScore) {
    if (!view || depth > 18) return;
    CGFloat score = 0;
    if (CEOrphanIsSidebarControlCandidate(view, window, &score) && (!*best || score > *bestScore)) { *best = view; *bestScore = score; }
    for (UIView *child in view.subviews) CEOrphanFindSidebarControl(child, window, depth + 1, best, bestScore);
}

static BOOL CEOrphanActivateSidebar(void) {
    UIWindow *window = CEKeyWindow(); if (!window) return NO;
    UIView *candidate = nil; CGFloat bestScore = -CGFLOAT_MAX;
    CEOrphanFindSidebarControl(window, window, 0, &candidate, &bestScore);
    if (!candidate) {
        CGPoint point = CGPointMake(34.0, window.safeAreaInsets.top + 26.0);
        UIView *hit = [window hitTest:point withEvent:nil];
        for (UIView *cursor = hit; cursor && cursor != window; cursor = cursor.superview) {
            if ([cursor isKindOfClass:UIControl.class] || (cursor.accessibilityTraits & UIAccessibilityTraitButton) != 0) { candidate = cursor; break; }
        }
    }
    if (!candidate) { NSLog(@"[ChatGPTEnhancer] manual reload could not find sidebar control"); return NO; }
    NSLog(@"[ChatGPTEnhancer] manual reload activating sidebar control class=%@ label=%@", NSStringFromClass(candidate.class), candidate.accessibilityLabel ?: @"<nil>");
    if ([candidate isKindOfClass:UIControl.class]) { [(UIControl *)candidate sendActionsForControlEvents:UIControlEventTouchUpInside]; return YES; }
    @try { if ([candidate accessibilityActivate]) return YES; } @catch (__unused NSException *exception) {}
    return NO;
}

static BOOL CEOrphanManualSelectCurrentHistoryItem(NSString *conversationID) {
    UIWindow *window = CEKeyWindow(); UIViewController *history = CEOrphanFindHistoryController(window.rootViewController, 0);
    UICollectionView *collection = history ? CEOrphanFindHistoryCollection(history.viewIfLoaded, 0) : nil;
    id dataSource = collection.dataSource; SEL itemSelector = NSSelectorFromString(@"itemIdentifierForIndexPath:"); SEL selectSelector = NSSelectorFromString(@"collectionView:didSelectItemAtIndexPath:");
    if (!history || !collection || !dataSource || ![dataSource respondsToSelector:itemSelector] || ![history respondsToSelector:selectSelector]) return NO;

    NSIndexPath *target = nil;
    if ([CEOrphanConfirmedHistoryConversationID isEqualToString:conversationID] && CEOrphanConfirmedHistoryIdentifier) {
        NSInteger sections = collection.numberOfSections;
        for (NSInteger section = 0; section < sections && !target; section++) {
            NSInteger items = [collection numberOfItemsInSection:section];
            for (NSInteger item = 0; item < items; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
                id identifier = ((id (*)(id, SEL, id))objc_msgSend)(dataSource, itemSelector, indexPath);
                BOOL equal = NO; @try { equal = identifier == CEOrphanConfirmedHistoryIdentifier || [identifier isEqual:CEOrphanConfirmedHistoryIdentifier]; } @catch (__unused NSException *exception) {}
                if (equal) { target = indexPath; break; }
            }
        }
        if (!target && CEOrphanConfirmedHistoryIndexPath.section < collection.numberOfSections && CEOrphanConfirmedHistoryIndexPath.item < [collection numberOfItemsInSection:CEOrphanConfirmedHistoryIndexPath.section]) {
            id identifier = ((id (*)(id, SEL, id))objc_msgSend)(dataSource, itemSelector, CEOrphanConfirmedHistoryIndexPath);
            BOOL equal = NO; @try { equal = identifier == CEOrphanConfirmedHistoryIdentifier || [identifier isEqual:CEOrphanConfirmedHistoryIdentifier]; } @catch (__unused NSException *exception) {}
            if (equal) target = CEOrphanConfirmedHistoryIndexPath;
        }
    }

    if (!target) {
        NSArray<NSIndexPath *> *selected = collection.indexPathsForSelectedItems;
        if (selected.count == 1) target = selected.firstObject;
    }

    if (!target) return CEOrphanReselectConversationInternal(conversationID, YES);
    [collection deselectItemAtIndexPath:target animated:NO];
    [collection selectItemAtIndexPath:target animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    ((void (*)(id, SEL, id, id))objc_msgSend)(history, selectSelector, collection, target);
    NSLog(@"[ChatGPTEnhancer] manual reload invoked exact/selected history row for %@ section=%ld item=%ld", conversationID, (long)target.section, (long)target.item);
    return YES;
}

static void CEOrphanManualReloadAttempt(NSString *conversationID, NSUInteger generation, NSUInteger attempt, void (^completion)(BOOL success)) {
    if (generation != CEOrphanManualReloadGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSDate *startedAt = NSDate.date;
    BOOL invoked = CEOrphanManualSelectCurrentHistoryItem(conversationID);
    if (invoked) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.80 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != CEOrphanManualReloadGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            if (CEOrphanRecentDetailRequestForConversationSince(conversationID, startedAt)) { if (completion) completion(YES); return; }
            if (attempt >= 5) { NSLog(@"[ChatGPTEnhancer] manual reload selection produced no official conversation request for %@", conversationID); if (completion) completion(NO); return; }
            CEOrphanActivateSidebar();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanManualReloadAttempt(conversationID, generation, attempt + 1, completion); });
        });
        return;
    }

    if (attempt >= 5) { NSLog(@"[ChatGPTEnhancer] manual reload failed after sidebar retries for %@", conversationID); if (completion) completion(NO); return; }
    CEOrphanActivateSidebar();
    NSTimeInterval delay = attempt < 2 ? 0.40 : 0.60;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanManualReloadAttempt(conversationID, generation, attempt + 1, completion); });
}

void CEOrphanForceReloadConversation(NSString *conversationID, void (^completion)(BOOL success)) {
    if (!conversationID.length) { if (completion) completion(NO); return; }
    CEOrphanInstallHistorySelectionCapture(0);
    NSUInteger generation = ++CEOrphanManualReloadGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanManualReloadAttempt(conversationID, generation, 0, completion); });
}

static void CEOrphanCheckForStaleStream(NSDate *cutoff, void (^completion)(BOOL hasStaleStream)) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!session || !cutoff) { completion(NO); return; }
    [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
        BOOL found = NO;
        for (NSURLSessionTask *task in tasks) {
            if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
            NSURLRequest *request = task.currentRequest ?: task.originalRequest;
            if (!CEOrphanLooksLikeConversationStream(request)) continue;
            NSDate *started = task.earliestBeginDate;
            if (!started || [started compare:cutoff] != NSOrderedDescending) { found = YES; break; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(found); });
    }];
}

static void CEOrphanProbeServer(NSString *conversationID, NSDate *cutoff, NSDate *activitySince, BOOL hadStreamHint, NSUInteger generation, NSUInteger attempt) {
    if (!conversationID.length || generation != CEOrphanGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSString *currentID = [CEConversationContext shared].conversationID;
    if (!currentID.length) {
        if (attempt < 3) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanProbeServer(conversationID, cutoff, activitySince, hadStreamHint, generation, attempt + 1); });
        return;
    }
    if (![currentID isEqualToString:conversationID]) return;
    BOOL loading = CEOrphanHasCentralLoadingIndicator();
    if (!hadStreamHint && !loading) return;
    if (CEOrphanRecentOfficialConversationActivitySince(activitySince)) { NSLog(@"[ChatGPTEnhancer] orphan recovery skipped because official conversation transport resumed"); return; }
    if (![[CEAPIClient shared] isReady]) {
        if (attempt < 3) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanProbeServer(conversationID, cutoff, activitySince, hadStreamHint, generation, attempt + 1); });
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (generation != CEOrphanGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        BOOL finished = !error && response.statusCode >= 200 && response.statusCode < 300 && CEOrphanConversationFinished(data);
        if (!finished) {
            if (attempt < 2) { NSTimeInterval delay = attempt == 0 ? 2.0 : 4.0; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanProbeServer(conversationID, cutoff, activitySince, hadStreamHint, generation, attempt + 1); }); }
            return;
        }
        CEOrphanCheckForStaleStream(cutoff, ^(BOOL hasStaleStream) {
            if (generation != CEOrphanGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            if (hasStaleStream) { NSLog(@"[ChatGPTEnhancer] orphan recovery found stale stream; foreground stream recovery will handle it"); return; }
            if (CEOrphanRecentOfficialConversationActivitySince(activitySince)) { NSLog(@"[ChatGPTEnhancer] orphan recovery saw fresh official conversation transport after server check"); return; }
            if (!CEOrphanReselectConversation(conversationID)) NSLog(@"[ChatGPTEnhancer] orphan recovery could not reselect completed conversation %@", conversationID);
        });
    }];
}

static void CEOrphanScheduleContextProbe(NSString *conversationID) {
    if (!conversationID.length) return;
    NSUInteger token = ++CEOrphanContextGeneration;
    NSDate *scheduledAt = NSDate.date;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CEOrphanContextGeneration || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        if (![[CEConversationContext shared].conversationID isEqualToString:conversationID] || !CEOrphanHasCentralLoadingIndicator()) return;
        NSUInteger generation = ++CEOrphanGeneration;
        CEOrphanProbeServer(conversationID, scheduledAt, scheduledAt, NO, generation, 0);
    });
}

static void CEOrphanCaptureBackgroundStreams(NSUInteger generation, NSString *conversationID) {
    NSURLSession *session = [CENetworkObserver shared].requestSession;
    if (!session || !conversationID.length) return;
    [session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
        BOOL found = NO;
        for (NSURLSessionTask *task in tasks) {
            if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
            if (CEOrphanLooksLikeConversationStream(task.currentRequest ?: task.originalRequest)) { found = YES; break; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == CEOrphanGeneration && [CEOrphanBackgroundConversationID isEqualToString:conversationID]) CEOrphanHadStreamAtBackground = found;
        });
    }];
}

static void CEOrphanInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CEOrphanInstallHistorySelectionCapture(0);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CEOrphanBackgroundDate = NSDate.date; CEOrphanForegroundDate = nil; CEOrphanBackgroundConversationID = [[CEConversationContext shared].conversationID copy]; CEOrphanHadStreamAtBackground = NO;
            NSUInteger generation = ++CEOrphanGeneration; CEOrphanCaptureBackgroundStreams(generation, CEOrphanBackgroundConversationID);
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            CEOrphanInstallHistorySelectionCapture(0);
            NSDate *backgroundDate = CEOrphanBackgroundDate; NSString *conversationID = [CEOrphanBackgroundConversationID copy];
            CEOrphanForegroundDate = NSDate.date; NSUInteger generation = ++CEOrphanGeneration;
            if (!backgroundDate || !conversationID.length || [NSDate.date timeIntervalSinceDate:backgroundDate] < 3.0) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                BOOL hadStream = CEOrphanHadStreamAtBackground;
                CEOrphanProbeServer(conversationID, backgroundDate, CEOrphanForegroundDate, hadStream, generation, 0);
            });
        }];
        [center addObserverForName:CEConversationContextDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NSString *conversationID = [[CEConversationContext shared].conversationID copy];
            if (conversationID.length) CEOrphanScheduleContextProbe(conversationID); else CEOrphanContextGeneration++;
        }];
        NSString *currentID = [CEConversationContext shared].conversationID; if (currentID.length) CEOrphanScheduleContextProbe(currentID);
        NSLog(@"[ChatGPTEnhancer] orphaned conversation recovery installed");
    });
}

__attribute__((constructor)) static void CEOrphanedConversationRecoveryEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEOrphanInstall(); });
    }
}
