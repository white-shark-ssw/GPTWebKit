#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"

static id CEIdentityLastIdentifier = nil;
static __weak UIView *CEIdentityLastTouchedView = nil;
static NSDate *CEIdentityLastUpdatedAt = nil;
static NSArray<CEConversationRecord *> *CEIdentityLastCandidates = nil;
static NSString *CEIdentityLastDebug = nil;

static NSString *CEIdentityTrimmedDescription(id object) {
    if (!object) return @"<nil>";
    NSString *text = nil;
    @try { text = [object description]; } @catch (__unused NSException *exception) {}
    if (!text.length) text = NSStringFromClass([object class]);
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return text.length > 360 ? [[text substringToIndex:360] stringByAppendingString:@"…"] : text;
}

static id CEIdentityValueForKey(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try { return [object valueForKey:key]; } @catch (__unused NSException *exception) { return nil; }
}

static void CEIdentityAddString(NSMutableOrderedSet<NSString *> *strings, NSString *text) {
    if (![text isKindOfClass:NSString.class] || strings.count >= 1200) return;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trim.length && trim.length <= 1200) [strings addObject:trim];
}

static void CEIdentityCollectObject(id object, NSUInteger depth, NSMutableSet<NSValue *> *visited, NSMutableOrderedSet<NSString *> *strings) {
    if (!object || depth > 6 || visited.count >= 1200 || strings.count >= 1200) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)object];
    if ([visited containsObject:key]) return;
    [visited addObject:key];

    if ([object isKindOfClass:NSString.class]) { CEIdentityAddString(strings, object); return; }
    if ([object isKindOfClass:NSUUID.class]) { CEIdentityAddString(strings, [object UUIDString]); return; }
    if ([object isKindOfClass:NSURL.class]) { CEIdentityAddString(strings, [object absoluteString]); return; }
    if ([object isKindOfClass:NSArray.class]) { for (id child in object) CEIdentityCollectObject(child, depth + 1, visited, strings); return; }
    if ([object isKindOfClass:NSSet.class]) { for (id child in object) CEIdentityCollectObject(child, depth + 1, visited, strings); return; }
    if ([object isKindOfClass:NSOrderedSet.class]) { for (id child in object) CEIdentityCollectObject(child, depth + 1, visited, strings); return; }
    if ([object isKindOfClass:NSDictionary.class]) {
        for (id child in [(NSDictionary *)object allKeys]) CEIdentityCollectObject(child, depth + 1, visited, strings);
        for (id child in [(NSDictionary *)object allValues]) CEIdentityCollectObject(child, depth + 1, visited, strings);
        return;
    }

    CEIdentityAddString(strings, CEIdentityTrimmedDescription(object));
    NSArray<NSString *> *knownKeys = @[@"base", @"sourceIndexPath", @"itemList", @"_itemList", @"id", @"menuChangeDetector", @"viewIdentity", @"kind"];
    for (NSString *knownKey in knownKeys) {
        id value = CEIdentityValueForKey(object, knownKey);
        if (value && value != object) CEIdentityCollectObject(value, depth + 1, visited, strings);
    }

    for (Class cls = object_getClass(object); cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0; Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count && visited.count < 1200; i++) {
            Ivar ivar = ivars[i]; const char *type = ivar_getTypeEncoding(ivar);
            if (!type || type[0] != '@') continue;
            id value = nil; @try { value = object_getIvar(object, ivar); } @catch (__unused NSException *exception) {}
            if (value && value != object) CEIdentityCollectObject(value, depth + 1, visited, strings);
        }
        if (ivars) free(ivars);
    }
}

static CEConversationRecord *CEIdentityRecordForID(NSString *conversationID) {
    if (!conversationID.length) return nil;
    CEConversationRecord *record = [[CECatalog shared] recordForID:conversationID];
    if (record) return record;
    CEConversationRecord *fallback = [CEConversationRecord new]; fallback.conversationID = conversationID; fallback.title = @"当前会话"; return fallback;
}

static NSArray<CEConversationRecord *> *CEIdentityCandidatesFromStrings(NSArray<NSString *> *strings) {
    NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet];
    for (NSString *text in strings) {
        NSString *cid = CEExtractConversationIDFromString(text);
        if (cid.length) [ids addObject:cid];
    }
    if (ids.count == 1) { CEConversationRecord *record = CEIdentityRecordForID(ids.firstObject); return record ? @[record] : @[]; }
    if (ids.count > 1) {
        NSMutableArray<CEConversationRecord *> *records = [NSMutableArray array];
        for (NSString *cid in ids) { CEConversationRecord *record = [[CECatalog shared] recordForID:cid]; if (record) [records addObject:record]; }
        if (records.count == 1) return records;
    }

    NSMutableOrderedSet<CEConversationRecord *> *uniqueTitleMatches = [NSMutableOrderedSet orderedSet];
    for (NSString *text in strings) {
        NSArray<CEConversationRecord *> *matches = [[CECatalog shared] recordsMatchingTitle:text];
        if (matches.count == 1) [uniqueTitleMatches addObject:matches.firstObject];
    }
    return uniqueTitleMatches.count == 1 ? @[uniqueTitleMatches.firstObject] : @[];
}

static UIView *CEIdentityMarkingView(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) if ([NSStringFromClass(cursor.class) containsString:@"LiftPreviewLabelMarkingView"]) return cursor;
    return nil;
}

static NSString *CEIdentityIvarDump(id object, NSString *label) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@Class=%@\n%@Description=%@\n", label, object ? NSStringFromClass([object class]) : @"<nil>", label, CEIdentityTrimmedDescription(object)];
    if (!object) return out;
    NSUInteger total = 0;
    for (Class cls = object_getClass(object); cls && cls != NSObject.class && total < 80; cls = class_getSuperclass(cls)) {
        unsigned int count = 0; Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count && total < 80; i++, total++) {
            Ivar ivar = ivars[i]; const char *name = ivar_getName(ivar); const char *type = ivar_getTypeEncoding(ivar); ptrdiff_t offset = ivar_getOffset(ivar);
            NSString *valueClass = @"", *valueDescription = @"";
            if (type && type[0] == '@') {
                id value = nil; @try { value = object_getIvar(object, ivar); } @catch (__unused NSException *exception) {}
                if (value) { valueClass = NSStringFromClass([value class]); valueDescription = CEIdentityTrimmedDescription(value); }
            }
            [out appendFormat:@"  %@.%s type=%s offset=0x%tx objectClass=%@ object=%@\n", NSStringFromClass(cls), name ?: "?", type ?: "?", offset, valueClass, valueDescription];
        }
        if (ivars) free(ivars);
    }
    return out;
}

static void CEIdentityResolveNow(void) {
    if (!CEIdentityLastIdentifier) { CEIdentityLastCandidates = nil; return; }
    NSMutableOrderedSet<NSString *> *strings = [NSMutableOrderedSet orderedSet]; NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    CEIdentityCollectObject(CEIdentityLastIdentifier, 0, visited, strings);
    UIView *marking = CEIdentityMarkingView(CEIdentityLastTouchedView);
    if (marking) CEIdentityCollectObject(marking, 0, visited, strings);
    CEIdentityLastCandidates = CEIdentityCandidatesFromStrings(strings.array);

    id base = CEIdentityValueForKey(CEIdentityLastIdentifier, @"base");
    id responderID = CEIdentityValueForKey(base, @"id");
    id itemList = CEIdentityValueForKey(base, @"itemList") ?: CEIdentityValueForKey(base, @"_itemList");
    id viewIdentity = CEIdentityValueForKey(marking, @"viewIdentity");
    NSMutableString *debug = [NSMutableString stringWithString:@"[Context identity]\n"];
    [debug appendFormat:@"resolvedCandidates=%lu\n", (unsigned long)CEIdentityLastCandidates.count];
    if (CEIdentityLastCandidates.count == 1) [debug appendFormat:@"resolvedID=%@\nresolvedTitle=%@\n", CEIdentityLastCandidates.firstObject.conversationID ?: @"<nil>", CEIdentityLastCandidates.firstObject.title ?: @"<nil>"];
    [debug appendString:CEIdentityIvarDump(CEIdentityLastIdentifier, @"identifier")];
    [debug appendString:CEIdentityIvarDump(base, @"base")];
    [debug appendString:CEIdentityIvarDump(responderID, @"responderID")];
    [debug appendString:CEIdentityIvarDump(itemList, @"itemList")];
    [debug appendString:CEIdentityIvarDump(marking, @"markingView")];
    [debug appendString:CEIdentityIvarDump(viewIdentity, @"viewIdentity")];
    NSUInteger count = MIN((NSUInteger)40, strings.count); [debug appendString:@"identityStrings:\n"];
    for (NSUInteger i = 0; i < count; i++) [debug appendFormat:@"IS%03lu: %@\n", (unsigned long)i, strings[i]];
    CEIdentityLastDebug = [debug copy]; CEIdentityLastUpdatedAt = [NSDate date];
}

static NSArray<CEConversationRecord *> *CEIdentityFreshCandidates(void) {
    if (!CEIdentityLastUpdatedAt || [[NSDate date] timeIntervalSinceDate:CEIdentityLastUpdatedAt] > 20.0) return @[];
    return CEIdentityLastCandidates ?: @[];
}

@implementation UIWindow (ChatGPTEnhancerContextIdentityTouch)
- (void)ceid_sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CGPoint point = [touch locationInView:self]; UIView *hit = [self hitTest:point withEvent:event];
        if (hit) CEIdentityLastTouchedView = hit;
    }
    [self ceid_sendEvent:event];
}
@end

@implementation UIContextMenuConfiguration (ChatGPTEnhancerContextIdentityResolver)
+ (instancetype)ceid_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider {
    CEIdentityLastIdentifier = (id)identifier; CEIdentityLastUpdatedAt = [NSDate date]; CEIdentityResolveNow();
    return [self ceid_configurationWithIdentifier:identifier previewProvider:previewProvider actionProvider:actionProvider];
}
@end

@implementation CEFeatures (ChatGPTEnhancerContextIdentityResolver)
+ (void)ceid_exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu {
    NSArray<CEConversationRecord *> *identity = CEIdentityFreshCandidates();
    [self ceid_exportCandidates:identity.count ? identity : candidates fromContextMenu:fromContextMenu];
}
+ (void)ceid_renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView {
    NSArray<CEConversationRecord *> *identity = CEIdentityFreshCandidates();
    [self ceid_renameCandidates:identity.count ? identity : candidates sourceView:sourceView];
}
@end

@implementation UIAlertAction (ChatGPTEnhancerContextIdentityDiagnostics)
+ (instancetype)ceid_actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^ _Nullable)(UIAlertAction *action))handler {
    if (![title isEqualToString:@"复制诊断"]) return [self ceid_actionWithTitle:title style:style handler:handler];
    void (^wrapped)(UIAlertAction *) = ^(UIAlertAction *action) {
        if (handler) handler(action);
        if (!CEIdentityLastDebug.length) return;
        NSString *base = UIPasteboard.generalPasteboard.string ?: @"";
        if ([base containsString:@"[Context identity]"]) return;
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n\n%@", base, CEIdentityLastDebug];
    };
    return [self ceid_actionWithTitle:title style:style handler:wrapped];
}
@end

__attribute__((constructor)) static void CEInstallContextIdentityResolver(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                static dispatch_once_t once; dispatch_once(&once, ^{
                    CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(ceid_sendEvent:));
                    SEL factory = @selector(configurationWithIdentifier:previewProvider:actionProvider:);
                    if ([UIContextMenuConfiguration respondsToSelector:factory]) CESwizzleClassMethod(UIContextMenuConfiguration.class, factory, @selector(ceid_configurationWithIdentifier:previewProvider:actionProvider:));
                    CESwizzleClassMethod(CEFeatures.class, @selector(exportCandidates:fromContextMenu:), @selector(ceid_exportCandidates:fromContextMenu:));
                    CESwizzleClassMethod(CEFeatures.class, @selector(renameCandidates:sourceView:), @selector(ceid_renameCandidates:sourceView:));
                    CESwizzleClassMethod(UIAlertAction.class, @selector(actionWithTitle:style:handler:), @selector(ceid_actionWithTitle:style:handler:));
                });
            });
        });
    }
}
