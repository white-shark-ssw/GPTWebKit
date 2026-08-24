#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <string.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Network/CEAPIClient.h"
#import "../Features/CEFeatures.h"

static CEConversationRecord *CEGenericResolvedRecord = nil;
static NSDate *CEGenericResolvedAt = nil;
static NSArray<NSString *> *CEGenericCandidateIDs = nil;
static NSDate *CEGenericCandidateAt = nil;
static NSString *CEGenericLastReport = nil;

static BOOL CEGenericMallocInfo(const void *pointer, size_t *sizeOut) {
    if (!pointer) return NO;
    uintptr_t raw = (uintptr_t)pointer; if (raw < 0x100000000ULL || (raw & 0x7ULL) != 0) return NO;
    malloc_zone_t *zone = malloc_zone_from_ptr(pointer); if (!zone) return NO;
    size_t size = malloc_size(pointer); if (size < 16 || size > 1024 * 1024) return NO;
    if (sizeOut) *sizeOut = size; return YES;
}

static BOOL CEGenericIsHex(uint8_t c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }

static BOOL CEGenericLooksLikeUUIDAt(const uint8_t *bytes, size_t length, size_t offset) {
    if (!bytes || offset + 36 > length) return NO;
    for (size_t i = 0; i < 36; i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) { if (bytes[offset + i] != '-') return NO; }
        else if (!CEGenericIsHex(bytes[offset + i])) return NO;
    }
    if (offset > 0 && (CEGenericIsHex(bytes[offset - 1]) || bytes[offset - 1] == '-')) return NO;
    if (offset + 36 < length && (CEGenericIsHex(bytes[offset + 36]) || bytes[offset + 36] == '-')) return NO;
    return YES;
}

static void CEGenericCollectUUIDs(const uint8_t *bytes, size_t length, NSUInteger depth, NSMutableDictionary<NSString *, NSNumber *> *matches) {
    if (!bytes || length < 36) return;
    for (size_t offset = 0; offset + 36 <= length; offset++) {
        if (!CEGenericLooksLikeUUIDAt(bytes, length, offset)) continue;
        NSString *value = [[[NSString alloc] initWithBytes:bytes + offset length:36 encoding:NSASCIIStringEncoding] lowercaseString];
        if (!value.length || [value isEqualToString:@"00000000-0000-0000-0000-000000000000"]) continue;
        NSNumber *old = matches[value]; if (!old || old.unsignedIntegerValue > depth) matches[value] = @(depth);
        offset += 35;
    }
}

static void CEGenericScanPointer(const void *pointer, NSUInteger depth, NSMutableSet<NSValue *> *visited, NSMutableDictionary<NSString *, NSNumber *> *matches, NSUInteger *allocationCount, NSUInteger *byteCount) {
    if (!pointer || depth > 5 || visited.count >= 140 || *allocationCount >= 140 || *byteCount >= 384 * 1024) return;
    size_t allocationSize = 0; if (!CEGenericMallocInfo(pointer, &allocationSize)) return;
    NSValue *key = [NSValue valueWithPointer:pointer]; if ([visited containsObject:key]) return; [visited addObject:key]; (*allocationCount)++;
    size_t scanLength = MIN(allocationSize, (size_t)8192); size_t remaining = 384 * 1024 - *byteCount; scanLength = MIN(scanLength, remaining); *byteCount += scanLength;
    CEGenericCollectUUIDs((const uint8_t *)pointer, scanLength, depth, matches);
    size_t pointerBytes = MIN(scanLength, (size_t)1536);
    for (size_t offset = 0; offset + sizeof(void *) <= pointerBytes && visited.count < 140; offset += sizeof(void *)) {
        uintptr_t raw = 0; memcpy(&raw, (const uint8_t *)pointer + offset, sizeof(raw)); if (!raw || (raw & 0x7ULL) != 0 || raw == (uintptr_t)pointer) continue;
        const void *child = (const void *)raw; size_t childSize = 0; if (!CEGenericMallocInfo(child, &childSize)) continue;
        CEGenericScanPointer(child, depth + 1, visited, matches, allocationCount, byteCount);
    }
}

static NSDictionary *CEGenericScanRoot(const void *pointer) {
    NSMutableSet<NSValue *> *visited = [NSMutableSet set]; NSMutableDictionary<NSString *, NSNumber *> *matches = [NSMutableDictionary dictionary]; NSUInteger allocations = 0, bytes = 0;
    CEGenericScanPointer(pointer, 0, visited, matches, &allocations, &bytes); return @{ @"matches": matches, @"allocations": @(allocations), @"bytes": @(bytes) };
}

static BOOL CEGenericIsOurAction(UIAction *action) { return [action.identifier hasPrefix:@"com.whiteshark.chatgptenhancer."]; }

static void CEGenericCollectActions(NSArray<UIMenuElement *> *elements, NSMutableArray<UIAction *> *actions) {
    for (UIMenuElement *element in elements ?: @[]) {
        if ([element isKindOfClass:UIAction.class]) [actions addObject:(UIAction *)element];
        else if ([element isKindOfClass:UIMenu.class]) CEGenericCollectActions(((UIMenu *)element).children, actions);
    }
}

static BOOL CEGenericLooksLikeHistoryMenu(NSArray<UIAction *> *actions) {
    NSUInteger officialMatches = 0;
    for (UIAction *action in actions) {
        if (CEGenericIsOurAction(action)) continue; NSString *title = action.title.lowercaseString ?: @"";
        if ([title containsString:@"重命名"] || [title containsString:@"rename"] || [title containsString:@"删除"] || [title containsString:@"delete"] || [title containsString:@"归档"] || [title containsString:@"archive"] || [title containsString:@"置顶"] || [title containsString:@"pin"]) officialMatches++;
    }
    return officialMatches >= 2;
}

static CEConversationRecord *CEGenericRecordForID(NSString *conversationID) {
    if (!conversationID.length) return nil;
    CEConversationRecord *record = [[CECatalog shared] recordForID:conversationID]; if (record) return record;
    record = [CEConversationRecord new]; record.conversationID = conversationID; record.title = @"当前会话"; return record;
}

static void CEGenericAppendReport(NSString *text) {
    if (!text.length) return;
    @synchronized (NSObject.class) { CEGenericLastReport = [NSString stringWithFormat:@"%@%@%@", CEGenericLastReport ?: @"", CEGenericLastReport.length ? @"\n" : @"", text]; }
}

static NSDictionary *CEGenericConversationContainer(NSData *data) {
    if (!data.length) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dict = (NSDictionary *)root;
    if ([dict[@"mapping"] isKindOfClass:NSDictionary.class] && dict[@"current_node"]) return dict;
    NSDictionary *conversation = [dict[@"conversation"] isKindOfClass:NSDictionary.class] ? dict[@"conversation"] : nil;
    return ([conversation[@"mapping"] isKindOfClass:NSDictionary.class] && conversation[@"current_node"]) ? conversation : nil;
}

static CEConversationRecord *CEGenericValidatedRecord(NSString *conversationID, NSData *data, NSHTTPURLResponse *response, NSError *error, NSString **lineOut) {
    NSDictionary *container = (!error && response.statusCode >= 200 && response.statusCode < 300) ? CEGenericConversationContainer(data) : nil;
    NSString *returnedID = [container[@"conversation_id"] isKindOfClass:NSString.class] ? container[@"conversation_id"] : [container[@"id"] isKindOfClass:NSString.class] ? container[@"id"] : nil;
    BOOL valid = container && (!returnedID.length || [returnedID caseInsensitiveCompare:conversationID] == NSOrderedSame);
    NSString *title = [container[@"title"] isKindOfClass:NSString.class] ? [container[@"title"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (lineOut) *lineOut = [NSString stringWithFormat:@"validate %@ status=%ld valid=%@ title=%@ error=%@", conversationID, (long)response.statusCode, valid ? @"YES" : @"NO", title.length ? title : @"<nil>", error ? error.localizedDescription : @"<nil>"];
    if (!valid) return nil;
    CEConversationRecord *record = CEGenericRecordForID(conversationID); if (title.length) { record.title = title; [[CECatalog shared] updateTitle:title forConversationID:conversationID]; }
    if (data.length && response.URL) [[CECatalog shared] ingestResponseData:data requestURL:response.URL];
    return record;
}

static void CEGenericValidateCandidateIDs(NSArray<NSString *> *candidateIDs, void (^completion)(CEConversationRecord *record)) {
    NSMutableOrderedSet<NSString *> *unique = [NSMutableOrderedSet orderedSet]; for (NSString *candidateID in candidateIDs ?: @[]) if (candidateID.length) [unique addObject:candidateID.lowercaseString];
    NSArray<NSString *> *ids = unique.array; if (!ids.count || ![CEAPIClient shared].isReady) { if (completion) completion(nil); return; }
    if (ids.count > 3) ids = [ids subarrayWithRange:NSMakeRange(0, 3)];
    __block NSUInteger pending = ids.count; __block NSMutableArray<CEConversationRecord *> *validRecords = [NSMutableArray array]; __block NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *conversationID in ids) {
        NSString *escaped = [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]; NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", escaped];
        [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
            NSString *line = nil; CEConversationRecord *record = CEGenericValidatedRecord(conversationID, data, response, error, &line); if (record) [validRecords addObject:record]; if (line.length) [lines addObject:line];
            if (--pending) return;
            CEConversationRecord *resolved = validRecords.count == 1 ? validRecords.firstObject : nil;
            if (resolved) { @synchronized (NSObject.class) { CEGenericResolvedRecord = resolved; CEGenericResolvedAt = [NSDate date]; } }
            NSMutableString *validation = [NSMutableString stringWithFormat:@"[Conversation API validation]\ncandidates=%@\n", [ids componentsJoinedByString:@", "]]; for (NSString *entry in lines) [validation appendFormat:@"%@\n", entry];
            if (resolved) [validation appendFormat:@"RESULT resolvedID=%@ title=%@", resolved.conversationID, resolved.title ?: @""]; else [validation appendFormat:@"RESULT unresolved validCount=%lu", (unsigned long)validRecords.count];
            CEGenericAppendReport(validation); if (completion) completion(resolved);
        }];
    }
}

static void CEGenericResolveMenu(UIMenu *menu, NSString *reason) {
    if (!menu) return;
    NSMutableArray<UIAction *> *actions = [NSMutableArray array]; CEGenericCollectActions(menu.children, actions); if (!CEGenericLooksLikeHistoryMenu(actions)) return;
    NSMutableDictionary<NSString *, NSNumber *> *scores = [NSMutableDictionary dictionary]; NSMutableDictionary<NSString *, NSNumber *> *supports = [NSMutableDictionary dictionary]; NSMutableDictionary<NSString *, NSNumber *> *bestDepths = [NSMutableDictionary dictionary]; NSMutableString *report = [NSMutableString stringWithFormat:@"[Generic UUID resolver]\nreason=%@ actionCount=%lu\n", reason ?: @"?", (unsigned long)actions.count];
    NSUInteger officialActionCount = 0;
    for (UIAction *action in actions) {
        if (CEGenericIsOurAction(action)) continue;
        id handler = nil; @try { handler = [action valueForKey:@"handler"]; } @catch (__unused NSException *exception) {}
        id handlerCopy = handler ? [handler copy] : nil; if (!handlerCopy) continue; officialActionCount++;
        NSDictionary *scan = CEGenericScanRoot((__bridge const void *)handlerCopy); NSDictionary<NSString *, NSNumber *> *matches = scan[@"matches"] ?: @{};
        [report appendFormat:@"%@ allocations=%@ bytes=%@ UUIDs=%lu", action.title ?: @"<untitled>", scan[@"allocations"] ?: @0, scan[@"bytes"] ?: @0, (unsigned long)matches.count];
        NSArray<NSString *> *sortedIDs = [matches.allKeys sortedArrayUsingSelector:@selector(compare:)]; NSUInteger shown = 0;
        for (NSString *conversationID in sortedIDs) {
            NSUInteger depth = matches[conversationID].unsignedIntegerValue; NSInteger weight = MAX((NSInteger)1, 7 - (NSInteger)depth);
            if (matches.count == 1) weight += 6;
            if ([[CECatalog shared] recordForID:conversationID]) weight += 2;
            scores[conversationID] = @([scores[conversationID] integerValue] + weight); supports[conversationID] = @([supports[conversationID] integerValue] + 1);
            NSNumber *oldDepth = bestDepths[conversationID]; if (!oldDepth || oldDepth.unsignedIntegerValue > depth) bestDepths[conversationID] = @(depth);
            if (shown++ < 6) [report appendFormat:@" %@^%lu", conversationID, (unsigned long)depth];
        }
        [report appendString:@"\n"];
    }
    NSArray<NSString *> *ranked = [scores.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger sa = [scores[a] integerValue], sb = [scores[b] integerValue]; if (sa != sb) return sa > sb ? NSOrderedAscending : NSOrderedDescending;
        NSInteger va = [supports[a] integerValue], vb = [supports[b] integerValue]; if (va != vb) return va > vb ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    for (NSUInteger i = 0; i < MIN((NSUInteger)8, ranked.count); i++) { NSString *cid = ranked[i]; [report appendFormat:@"rank%lu %@ score=%@ support=%@ depth=%@ known=%@\n", (unsigned long)i, cid, scores[cid], supports[cid], bestDepths[cid], [[CECatalog shared] recordForID:cid] ? @"YES" : @"NO"]; }
    NSString *winner = ranked.firstObject; NSInteger winnerScore = winner ? [scores[winner] integerValue] : 0; NSInteger winnerSupport = winner ? [supports[winner] integerValue] : 0; NSInteger secondScore = ranked.count > 1 ? [scores[ranked[1]] integerValue] : 0; NSInteger secondSupport = ranked.count > 1 ? [supports[ranked[1]] integerValue] : 0;
    BOOL supportStrong = winnerSupport >= 2 || (officialActionCount == 1 && winnerSupport == 1); BOOL marginStrong = ranked.count <= 1 || winnerScore - secondScore >= 4 || winnerSupport - secondSupport >= 2;
    CEConversationRecord *resolved = (winner.length && winnerScore >= 12 && supportStrong && marginStrong) ? CEGenericRecordForID(winner) : nil;
    NSMutableArray<NSString *> *validationIDs = [NSMutableArray array]; for (NSString *cid in ranked) { if ([scores[cid] integerValue] < 8 || [supports[cid] integerValue] < 2) continue; [validationIDs addObject:cid]; if (validationIDs.count >= 3) break; }
    if (resolved) [report appendFormat:@"CONSENSUS resolvedID=%@ title=%@ score=%ld support=%ld\n", resolved.conversationID, resolved.title ?: @"", (long)winnerScore, (long)winnerSupport];
    else [report appendFormat:@"CONSENSUS unresolved topScore=%ld topSupport=%ld secondScore=%ld secondSupport=%ld validationCandidates=%@\n", (long)winnerScore, (long)winnerSupport, (long)secondScore, (long)secondSupport, [validationIDs componentsJoinedByString:@", "]];
    @synchronized (NSObject.class) { CEGenericResolvedRecord = resolved; CEGenericResolvedAt = resolved ? [NSDate date] : nil; CEGenericCandidateIDs = [validationIDs copy]; CEGenericCandidateAt = validationIDs.count ? [NSDate date] : nil; CEGenericLastReport = report; }
}

static CEConversationRecord *CEGenericFreshRecord(void) {
    @synchronized (NSObject.class) { return (CEGenericResolvedRecord && CEGenericResolvedAt && [[NSDate date] timeIntervalSinceDate:CEGenericResolvedAt] <= 20.0) ? CEGenericResolvedRecord : nil; }
}

static NSArray<NSString *> *CEGenericFreshCandidateIDs(void) {
    @synchronized (NSObject.class) { return (CEGenericCandidateIDs.count && CEGenericCandidateAt && [[NSDate date] timeIntervalSinceDate:CEGenericCandidateAt] <= 20.0) ? [CEGenericCandidateIDs copy] : @[]; }
}

@implementation UIContextMenuConfiguration (ChatGPTEnhancerGenericUUID)
+ (instancetype)cegeneric_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider {
    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) { UIMenu *menu = actionProvider ? actionProvider(suggestedActions) : [UIMenu menuWithTitle:@"" children:suggestedActions]; CEGenericResolveMenu(menu, @"actionProvider"); return menu; };
    return [self cegeneric_configurationWithIdentifier:identifier previewProvider:previewProvider actionProvider:wrapped];
}
@end

@implementation UIMenu (ChatGPTEnhancerGenericUUID)
- (UIMenu *)cegeneric_menuByReplacingChildren:(NSArray<UIMenuElement *> *)children { UIMenu *result = [self cegeneric_menuByReplacingChildren:children]; CEGenericResolveMenu(result, @"menuByReplacingChildren"); return result; }
@end

@implementation CEFeatures (ChatGPTEnhancerGenericUUID)
+ (void)cegeneric_exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu {
    if (candidates.count) { [self cegeneric_exportCandidates:candidates fromContextMenu:fromContextMenu]; return; }
    CEConversationRecord *record = CEGenericFreshRecord(); if (record) { [self cegeneric_exportCandidates:@[record] fromContextMenu:fromContextMenu]; return; }
    NSArray<NSString *> *ids = CEGenericFreshCandidateIDs(); if (!ids.count || ![CEAPIClient shared].isReady) { [self cegeneric_exportCandidates:candidates fromContextMenu:fromContextMenu]; return; }
    CEShowMessage(@"正在识别会话…"); CEGenericValidateCandidateIDs(ids, ^(CEConversationRecord *validated) { [self cegeneric_exportCandidates:validated ? @[validated] : candidates fromContextMenu:fromContextMenu]; });
}
+ (void)cegeneric_renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView {
    if (candidates.count) { [self cegeneric_renameCandidates:candidates sourceView:sourceView]; return; }
    CEConversationRecord *record = CEGenericFreshRecord(); if (record) { [self cegeneric_renameCandidates:@[record] sourceView:sourceView]; return; }
    NSArray<NSString *> *ids = CEGenericFreshCandidateIDs(); if (!ids.count || ![CEAPIClient shared].isReady) { [self cegeneric_renameCandidates:candidates sourceView:sourceView]; return; }
    CEShowMessage(@"正在识别会话…"); CEGenericValidateCandidateIDs(ids, ^(CEConversationRecord *validated) { [self cegeneric_renameCandidates:validated ? @[validated] : candidates sourceView:sourceView]; });
}
@end

@implementation UIAlertAction (ChatGPTEnhancerGenericUUIDDiagnostics)
+ (instancetype)cegeneric_actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^ _Nullable)(UIAlertAction *action))handler {
    if (![title isEqualToString:@"复制诊断"]) return [self cegeneric_actionWithTitle:title style:style handler:handler];
    void (^wrapped)(UIAlertAction *) = ^(UIAlertAction *action) { if (handler) handler(action); NSString *report = nil; @synchronized (NSObject.class) { report = CEGenericLastReport; } if (!report.length) return; NSString *base = UIPasteboard.generalPasteboard.string ?: @""; UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n\n%@", base, report]; };
    return [self cegeneric_actionWithTitle:title style:style handler:wrapped];
}
@end

__attribute__((constructor)) static void CEInstallGenericUUIDResolver(void) {
    @autoreleasepool { if (!CETargetApp()) return; dispatch_async(dispatch_get_main_queue(), ^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ static dispatch_once_t once; dispatch_once(&once, ^{
        SEL factory = @selector(configurationWithIdentifier:previewProvider:actionProvider:); if ([UIContextMenuConfiguration respondsToSelector:factory]) CESwizzleClassMethod(UIContextMenuConfiguration.class, factory, @selector(cegeneric_configurationWithIdentifier:previewProvider:actionProvider:));
        if ([UIMenu instancesRespondToSelector:@selector(menuByReplacingChildren:)]) CESwizzleInstanceMethod(UIMenu.class, @selector(menuByReplacingChildren:), @selector(cegeneric_menuByReplacingChildren:));
        CESwizzleClassMethod(CEFeatures.class, @selector(exportCandidates:fromContextMenu:), @selector(cegeneric_exportCandidates:fromContextMenu:)); CESwizzleClassMethod(CEFeatures.class, @selector(renameCandidates:sourceView:), @selector(cegeneric_renameCandidates:sourceView:)); CESwizzleClassMethod(UIAlertAction.class, @selector(actionWithTitle:style:handler:), @selector(cegeneric_actionWithTitle:style:handler:));
    }); }); }); }
}
