#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <string.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"

static __weak UIView *CEDeepLastTouchedView = nil;
static id CEDeepLastIdentifier = nil;
static NSDate *CEDeepLastMenuAt = nil;
static CEConversationRecord *CEDeepResolvedRecord = nil;
static NSMutableArray<NSString *> *CEDeepMenuSnapshots = nil;

static NSString *CEDeepTrim(NSString *text, NSUInteger limit) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *value = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return value.length > limit ? [[value substringToIndex:limit] stringByAppendingString:@"…"] : value;
}

static NSDictionary<NSString *, CEConversationRecord *> *CEDeepCatalogByID(void) {
    @try { id value = [[CECatalog shared] valueForKey:@"byID"]; return [value isKindOfClass:NSDictionary.class] ? [value copy] : @{}; }
    @catch (__unused NSException *exception) { return @{}; }
}

static BOOL CEDeepMallocInfo(const void *pointer, size_t *sizeOut) {
    if (!pointer) return NO;
    uintptr_t raw = (uintptr_t)pointer; if (raw < 0x100000000ULL || (raw & 0x7ULL) != 0) return NO;
    malloc_zone_t *zone = malloc_zone_from_ptr(pointer); if (!zone) return NO;
    size_t size = malloc_size(pointer); if (size < 16 || size > 1024 * 1024) return NO;
    if (sizeOut) *sizeOut = size; return YES;
}

static BOOL CEDeepBytesContain(const uint8_t *bytes, size_t length, const uint8_t *needle, size_t needleLength) {
    if (!bytes || !needle || !needleLength || length < needleLength) return NO;
    size_t offset = 0;
    while (offset + needleLength <= length) {
        const void *hit = memchr(bytes + offset, needle[0], length - offset - needleLength + 1); if (!hit) return NO;
        size_t index = (const uint8_t *)hit - bytes; if (memcmp(bytes + index, needle, needleLength) == 0) return YES; offset = index + 1;
    }
    return NO;
}

static void CEDeepRecordMatchesInBytes(const uint8_t *bytes, size_t length, NSDictionary<NSString *, CEConversationRecord *> *catalog, NSUInteger depth, NSString *path, NSMutableDictionary<NSString *, NSDictionary *> *matches) {
    for (NSString *conversationID in catalog) {
        NSData *utf8 = [conversationID dataUsingEncoding:NSUTF8StringEncoding]; const uint8_t *needle = (const uint8_t *)utf8.bytes;
        if (!utf8.length || !CEDeepBytesContain(bytes, length, needle, utf8.length)) continue;
        NSDictionary *old = matches[conversationID]; if (!old || [old[@"depth"] unsignedIntegerValue] > depth) matches[conversationID] = @{ @"depth": @(depth), @"path": path ?: @"root" };
    }
}

static void CEDeepScanPointer(const void *pointer, NSDictionary<NSString *, CEConversationRecord *> *catalog, NSUInteger depth, NSString *path, NSMutableSet<NSValue *> *visited, NSMutableDictionary<NSString *, NSDictionary *> *matches, NSUInteger *allocationCount, NSUInteger *byteCount) {
    if (!pointer || depth > 5 || visited.count >= 180 || *allocationCount >= 180 || *byteCount >= 512 * 1024) return;
    size_t allocationSize = 0; if (!CEDeepMallocInfo(pointer, &allocationSize)) return;
    NSValue *key = [NSValue valueWithPointer:pointer]; if ([visited containsObject:key]) return; [visited addObject:key]; (*allocationCount)++;
    size_t scanLength = MIN(allocationSize, (size_t)8192); size_t remaining = 512 * 1024 - *byteCount; scanLength = MIN(scanLength, remaining); *byteCount += scanLength;
    CEDeepRecordMatchesInBytes((const uint8_t *)pointer, scanLength, catalog, depth, path, matches);
    size_t pointerBytes = MIN(scanLength, (size_t)1536);
    for (size_t offset = 0; offset + sizeof(void *) <= pointerBytes && visited.count < 180; offset += sizeof(void *)) {
        uintptr_t raw = 0; memcpy(&raw, (const uint8_t *)pointer + offset, sizeof(raw)); if (!raw || (raw & 0x7ULL) != 0 || raw == (uintptr_t)pointer) continue;
        const void *child = (const void *)raw; size_t childSize = 0; if (!CEDeepMallocInfo(child, &childSize)) continue;
        NSString *childPath = [NSString stringWithFormat:@"%@ -> +0x%zx[%zu]", path ?: @"root", offset, childSize]; CEDeepScanPointer(child, catalog, depth + 1, childPath, visited, matches, allocationCount, byteCount);
    }
}

static NSDictionary *CEDeepScanRoot(const void *pointer, NSString *label, NSDictionary<NSString *, CEConversationRecord *> *catalog) {
    NSMutableSet<NSValue *> *visited = [NSMutableSet set]; NSMutableDictionary<NSString *, NSDictionary *> *matches = [NSMutableDictionary dictionary]; NSUInteger allocations = 0, bytes = 0;
    CEDeepScanPointer(pointer, catalog, 0, label ?: @"root", visited, matches, &allocations, &bytes); return @{ @"matches": matches, @"allocations": @(allocations), @"bytes": @(bytes) };
}

static NSString *CEDeepScanDescription(NSDictionary *scan) {
    NSDictionary *matches = scan[@"matches"] ?: @{}; NSMutableString *out = [NSMutableString stringWithFormat:@"scan allocations=%@ bytes=%@ matches=%lu", scan[@"allocations"] ?: @0, scan[@"bytes"] ?: @0, (unsigned long)matches.count];
    for (NSString *conversationID in [matches.allKeys sortedArrayUsingSelector:@selector(compare:)]) { NSDictionary *hit = matches[conversationID]; [out appendFormat:@"\n      UUID=%@ depth=%@ path=%@", conversationID, hit[@"depth"] ?: @"?", hit[@"path"] ?: @"?"]; }
    return out;
}

static BOOL CEDeepIsOurAction(UIAction *action) { return [action.identifier hasPrefix:@"com.whiteshark.chatgptenhancer."]; }

static void CEDeepCollectActions(NSArray<UIMenuElement *> *elements, NSMutableArray<UIAction *> *actions, NSMutableArray<NSString *> *deferred) {
    for (UIMenuElement *element in elements ?: @[]) {
        if ([element isKindOfClass:UIAction.class]) [actions addObject:(UIAction *)element];
        else if ([element isKindOfClass:UIMenu.class]) CEDeepCollectActions(((UIMenu *)element).children, actions, deferred);
        else if ([NSStringFromClass(element.class) containsString:@"DeferredMenu"]) [deferred addObject:NSStringFromClass(element.class)];
    }
}

static BOOL CEDeepLooksLikeHistoryConversationMenu(NSArray<UIAction *> *actions) {
    for (UIAction *action in actions) {
        if (CEDeepIsOurAction(action)) continue; NSString *title = action.title.lowercaseString ?: @"";
        if ([title containsString:@"重命名"] || [title containsString:@"rename"] || [title containsString:@"删除"] || [title containsString:@"delete"] || [title containsString:@"归档"] || [title containsString:@"archive"]) return YES;
    }
    return NO;
}

static void CEDeepVoteSingleMatch(NSDictionary *scan, NSMutableDictionary<NSString *, NSNumber *> *votes) {
    NSDictionary *matches = scan[@"matches"]; if (matches.count != 1) return; NSString *cid = matches.allKeys.firstObject; votes[cid] = @([votes[cid] integerValue] + 1);
}

static NSString *CEDeepInteractionReport(UIView *sourceView, NSDictionary<NSString *, CEConversationRecord *> *catalog, NSMutableDictionary<NSString *, NSNumber *> *votes) {
    NSMutableString *out = [NSMutableString stringWithString:@"[Context-menu interactions]\n"]; NSUInteger level = 0;
    for (UIView *view = sourceView; view && level < 14; view = view.superview, level++) {
        [out appendFormat:@"view%02lu=%@ frame=%@\n", (unsigned long)level, NSStringFromClass(view.class), NSStringFromCGRect([view convertRect:view.bounds toView:CEKeyWindow()])];
        for (id<UIInteraction> interaction in view.interactions ?: @[]) {
            id delegate = [interaction isKindOfClass:UIContextMenuInteraction.class] ? ((UIContextMenuInteraction *)interaction).delegate : nil;
            [out appendFormat:@"  interaction=%@ delegate=%@\n", NSStringFromClass([interaction class]), delegate ? NSStringFromClass([delegate class]) : @"<nil>"];
            if (delegate) { NSDictionary *scan = CEDeepScanRoot((__bridge const void *)delegate, @"interactionDelegate", catalog); [out appendFormat:@"    %@\n", CEDeepScanDescription(scan)]; CEDeepVoteSingleMatch(scan, votes); }
        }
        for (UIGestureRecognizer *gesture in view.gestureRecognizers ?: @[]) [out appendFormat:@"  gesture=%@ delegate=%@ state=%ld\n", NSStringFromClass(gesture.class), gesture.delegate ? NSStringFromClass([(id)gesture.delegate class]) : @"<nil>", (long)gesture.state];
    }
    return out;
}

static void CEDeepStoreSnapshot(NSString *snapshot) {
    if (!snapshot.length) return; @synchronized (NSObject.class) { if (!CEDeepMenuSnapshots) CEDeepMenuSnapshots = [NSMutableArray array]; [CEDeepMenuSnapshots addObject:snapshot]; while (CEDeepMenuSnapshots.count > 4) [CEDeepMenuSnapshots removeObjectAtIndex:0]; }
}

static void CEDeepCaptureMenu(UIMenu *menu, id identifier, UIView *sourceView, NSString *reason) {
    if (!menu) return; NSMutableArray<UIAction *> *actions = [NSMutableArray array]; NSMutableArray<NSString *> *deferred = [NSMutableArray array]; CEDeepCollectActions(menu.children, actions, deferred); if (!CEDeepLooksLikeHistoryConversationMenu(actions)) return;
    NSDictionary<NSString *, CEConversationRecord *> *catalog = CEDeepCatalogByID(); if (!catalog.count) return; NSMutableDictionary<NSString *, NSNumber *> *votes = [NSMutableDictionary dictionary];
    NSMutableString *report = [NSMutableString stringWithFormat:@"[Deep menu capture]\nreason=%@\ntime=%@\nidentifierClass=%@\nidentifier=%@\nmenuIdentifier=%@\nmenuTitle=%@\nactionCount=%lu\ndeferred=%@\n", reason ?: @"?", [NSDate date], identifier ? NSStringFromClass([identifier class]) : @"<nil>", CEDeepTrim([identifier description], 260), menu.identifier ?: @"", menu.title ?: @"", (unsigned long)actions.count, deferred];
    if (identifier) {
        NSDictionary *identityScan = CEDeepScanRoot((__bridge const void *)identifier, @"contextIdentifier", catalog); [report appendFormat:@"identity %@\n", CEDeepScanDescription(identityScan)]; CEDeepVoteSingleMatch(identityScan, votes);
        size_t identitySize = 0; if (CEDeepMallocInfo((__bridge const void *)identifier, &identitySize)) { size_t rawLength = MIN(identitySize, (size_t)64); [report appendFormat:@"identityRawWords size=%zu:", identitySize]; for (size_t offset = 0; offset + sizeof(uintptr_t) <= rawLength; offset += sizeof(uintptr_t)) { uintptr_t word = 0; memcpy(&word, (const uint8_t *)(__bridge const void *)identifier + offset, sizeof(word)); [report appendFormat:@" +0x%zx=0x%016llx", offset, (unsigned long long)word]; } [report appendString:@"\n"]; }
    }
    NSUInteger index = 0;
    for (UIAction *action in actions) {
        id handler = nil; @try { handler = [action valueForKey:@"handler"]; } @catch (__unused NSException *exception) {} id handlerCopy = handler ? [handler copy] : nil;
        [report appendFormat:@"action%02lu title=%@ identifier=%@ class=%@ handlerClass=%@\n", (unsigned long)index++, action.title ?: @"", action.identifier ?: @"", NSStringFromClass(action.class), handlerCopy ? NSStringFromClass([handlerCopy class]) : @"<nil>"];
        if (!handlerCopy || CEDeepIsOurAction(action)) continue; NSDictionary *scan = CEDeepScanRoot((__bridge const void *)handlerCopy, [NSString stringWithFormat:@"handler(%@)", action.title ?: @""], catalog); [report appendFormat:@"    %@\n", CEDeepScanDescription(scan)]; CEDeepVoteSingleMatch(scan, votes);
    }
    [report appendString:CEDeepInteractionReport(sourceView, catalog, votes)]; NSArray<NSString *> *votedIDs = [votes keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }]; [report appendString:@"votes:"]; for (NSString *cid in votedIDs) [report appendFormat:@" %@=%@", cid, votes[cid]]; [report appendString:@"\n"];
    CEConversationRecord *resolved = nil; if (votedIDs.count == 1 && [votes[votedIDs.firstObject] integerValue] >= 2) resolved = catalog[votedIDs.firstObject];
    if (resolved) [report appendFormat:@"CONSENSUS resolvedID=%@ title=%@ votes=%@\n", resolved.conversationID, resolved.title ?: @"", votes[resolved.conversationID]]; else [report appendString:@"CONSENSUS unresolved\n"];
    CEDeepLastIdentifier = identifier; CEDeepLastMenuAt = [NSDate date]; CEDeepResolvedRecord = resolved; CEDeepStoreSnapshot(report);
}

static void CEDeepAppendRuntimeClass(Class cls, NSMutableString *out) {
    [out appendFormat:@"CLASS %@ instanceSize=%zu\n", NSStringFromClass(cls), class_getInstanceSize(cls)]; unsigned int count = 0; Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned int i = 0; i < count && i < 48; i++) [out appendFormat:@"  ivar %s type=%s offset=0x%tx\n", ivar_getName(ivars[i]) ?: "?", ivar_getTypeEncoding(ivars[i]) ?: "?", ivar_getOffset(ivars[i])]; if (ivars) free(ivars);
    count = 0; objc_property_t *properties = class_copyPropertyList(cls, &count); for (unsigned int i = 0; i < count && i < 36; i++) [out appendFormat:@"  property %s attrs=%s\n", property_getName(properties[i]) ?: "?", property_getAttributes(properties[i]) ?: "?"]; if (properties) free(properties);
    count = 0; Method *methods = class_copyMethodList(cls, &count); for (unsigned int i = 0; i < count && i < 48; i++) [out appendFormat:@"  - %@ | %s\n", NSStringFromSelector(method_getName(methods[i])), method_getTypeEncoding(methods[i]) ?: ""]; if (methods) free(methods);
}

static NSString *CEDeepHistoryRuntimeReport(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"[ChatGPTHistory runtime]\n"]; int count = objc_getClassList(NULL, 0); if (count <= 0) return out; Class *classes = (Class *)calloc((size_t)count, sizeof(Class)); count = objc_getClassList(classes, count); NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (int i = 0; i < count; i++) { NSString *name = NSStringFromClass(classes[i]); NSString *lower = name.lowercaseString; if ([lower containsString:@"chatgpthistory"] || [lower containsString:@"historysidemenu"] || [lower containsString:@"renameconversationalert"] || [lower containsString:@"historyviewcontroller"]) [names addObject:name]; }
    free(classes); [names sortUsingSelector:@selector(compare:)]; NSUInteger limit = MIN((NSUInteger)70, names.count); for (NSUInteger i = 0; i < limit; i++) { Class cls = NSClassFromString(names[i]); if (cls) CEDeepAppendRuntimeClass(cls, out); } return out;
}

static void CEDeepAppendLiveControllers(UIViewController *vc, NSUInteger depth, NSDictionary<NSString *, CEConversationRecord *> *catalog, NSMutableString *out) {
    if (!vc || depth > 12) return; NSString *name = NSStringFromClass(vc.class); NSString *lower = name.lowercaseString;
    if ([lower containsString:@"chatgpthistory"] || [lower containsString:@"historyviewcontroller"] || [lower containsString:@"renameconversationalert"]) {
        [out appendFormat:@"LIVE %@\n", name]; NSDictionary *scan = CEDeepScanRoot((__bridge const void *)vc, [NSString stringWithFormat:@"live(%@)", name], catalog); [out appendFormat:@"  %@\n", CEDeepScanDescription(scan)];
        for (Class cls = vc.class; cls && cls != UIViewController.class; cls = class_getSuperclass(cls)) { unsigned int count = 0; Ivar *ivars = class_copyIvarList(cls, &count); for (unsigned int i = 0; i < count && i < 48; i++) { Ivar ivar = ivars[i]; const char *type = ivar_getTypeEncoding(ivar); NSString *objectClass = @""; if (type && type[0] == '@') { id value = nil; @try { value = object_getIvar(vc, ivar); } @catch (__unused NSException *exception) {} if (value) objectClass = NSStringFromClass([value class]); } [out appendFormat:@"  %@.%s type=%s offset=0x%tx objectClass=%@\n", NSStringFromClass(cls), ivar_getName(ivar) ?: "?", type ?: "?", ivar_getOffset(ivar), objectClass]; } if (ivars) free(ivars); }
    }
    if (vc.presentedViewController) CEDeepAppendLiveControllers(vc.presentedViewController, depth + 1, catalog, out); for (UIViewController *child in vc.childViewControllers) CEDeepAppendLiveControllers(child, depth + 1, catalog, out);
}

static NSString *CEDeepFullDiagnostic(void) {
    NSMutableString *out = [NSMutableString string]; @synchronized (NSObject.class) { [out appendFormat:@"[Deep diagnostic state]\nlastMenuAge=%@\nresolvedID=%@\nresolvedTitle=%@\nsnapshotCount=%lu\n", CEDeepLastMenuAt ? [NSString stringWithFormat:@"%.2fs", [[NSDate date] timeIntervalSinceDate:CEDeepLastMenuAt]] : @"<nil>", CEDeepResolvedRecord.conversationID ?: @"<nil>", CEDeepResolvedRecord.title ?: @"<nil>", (unsigned long)CEDeepMenuSnapshots.count]; NSUInteger i = 0; for (NSString *snapshot in CEDeepMenuSnapshots ?: @[]) [out appendFormat:@"\n===== SNAPSHOT %lu =====\n%@\n", (unsigned long)i++, snapshot]; }
    [out appendFormat:@"\n%@\n", CEDeepHistoryRuntimeReport()]; [out appendString:@"\n[Live ChatGPTHistory controllers]\n"]; CEDeepAppendLiveControllers(CEKeyWindow().rootViewController, 0, CEDeepCatalogByID(), out); return out;
}

static CEConversationRecord *CEDeepFreshResolvedRecord(void) { return (CEDeepResolvedRecord && CEDeepLastMenuAt && [[NSDate date] timeIntervalSinceDate:CEDeepLastMenuAt] <= 20.0) ? CEDeepResolvedRecord : nil; }

@implementation UIWindow (ChatGPTEnhancerDeepTouch)
- (void)cedeep_sendEvent:(UIEvent *)event { for (UITouch *touch in event.allTouches) if (touch.phase == UITouchPhaseBegan) { CGPoint point = [touch locationInView:self]; UIView *hit = [self hitTest:point withEvent:event]; if (hit) CEDeepLastTouchedView = hit; } [self cedeep_sendEvent:event]; }
@end

@implementation UIContextMenuConfiguration (ChatGPTEnhancerDeepMenu)
+ (instancetype)cedeep_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider {
    __weak UIView *source = CEDeepLastTouchedView; id capturedIdentifier = (id)identifier;
    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) { UIMenu *menu = actionProvider ? actionProvider(suggestedActions) : [UIMenu menuWithTitle:@"" children:suggestedActions]; if (menu) CEDeepCaptureMenu(menu, capturedIdentifier, source, @"actionProvider"); return menu; };
    return [self cedeep_configurationWithIdentifier:identifier previewProvider:previewProvider actionProvider:wrapped];
}
@end

@implementation UIMenu (ChatGPTEnhancerDeepReplacement)
- (UIMenu *)cedeep_menuByReplacingChildren:(NSArray<UIMenuElement *> *)children { UIMenu *result = [self cedeep_menuByReplacingChildren:children]; if (CEDeepLastMenuAt && [[NSDate date] timeIntervalSinceDate:CEDeepLastMenuAt] < 20.0) CEDeepCaptureMenu(result, CEDeepLastIdentifier, CEDeepLastTouchedView, @"menuByReplacingChildren"); return result; }
@end

@implementation CEFeatures (ChatGPTEnhancerDeepResolver)
+ (void)cedeep_exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu { CEConversationRecord *record = CEDeepFreshResolvedRecord(); [self cedeep_exportCandidates:record ? @[record] : candidates fromContextMenu:fromContextMenu]; }
+ (void)cedeep_renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView { CEConversationRecord *record = CEDeepFreshResolvedRecord(); [self cedeep_renameCandidates:record ? @[record] : candidates sourceView:sourceView]; }
@end

@implementation UIAlertAction (ChatGPTEnhancerDeepDiagnostics)
+ (instancetype)cedeep_actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^ _Nullable)(UIAlertAction *action))handler {
    if (![title isEqualToString:@"复制诊断"]) return [self cedeep_actionWithTitle:title style:style handler:handler];
    void (^wrapped)(UIAlertAction *) = ^(UIAlertAction *action) { if (handler) handler(action); NSString *deep = CEDeepFullDiagnostic(); if (!deep.length) return; NSString *base = UIPasteboard.generalPasteboard.string ?: @""; UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n\n%@", base, deep]; };
    return [self cedeep_actionWithTitle:title style:style handler:wrapped];
}
@end

__attribute__((constructor)) static void CEInstallDeepContextDiagnostics(void) {
    @autoreleasepool { if (!CETargetApp()) return; dispatch_async(dispatch_get_main_queue(), ^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ static dispatch_once_t once; dispatch_once(&once, ^{
        CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(cedeep_sendEvent:));
        SEL factory = @selector(configurationWithIdentifier:previewProvider:actionProvider:); if ([UIContextMenuConfiguration respondsToSelector:factory]) CESwizzleClassMethod(UIContextMenuConfiguration.class, factory, @selector(cedeep_configurationWithIdentifier:previewProvider:actionProvider:));
        if ([UIMenu instancesRespondToSelector:@selector(menuByReplacingChildren:)]) CESwizzleInstanceMethod(UIMenu.class, @selector(menuByReplacingChildren:), @selector(cedeep_menuByReplacingChildren:));
        CESwizzleClassMethod(CEFeatures.class, @selector(exportCandidates:fromContextMenu:), @selector(cedeep_exportCandidates:fromContextMenu:)); CESwizzleClassMethod(CEFeatures.class, @selector(renameCandidates:sourceView:), @selector(cedeep_renameCandidates:sourceView:)); CESwizzleClassMethod(UIAlertAction.class, @selector(actionWithTitle:style:handler:), @selector(cedeep_actionWithTitle:style:handler:));
    }); }); }); }
}
