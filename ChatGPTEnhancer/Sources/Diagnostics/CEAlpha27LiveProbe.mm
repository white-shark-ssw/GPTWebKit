#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <dlfcn.h>
#import "../Core/CECore.h"
#import "CERecoveryDiagnostics.h"

static __weak UIViewController *CEAlpha28ActiveMessages = nil;
static IMP CEAlpha28PriorDidAppear = NULL;
static IMP CEAlpha28PriorDidDisappear = NULL;

static Class CEAlpha28Class(NSString *name) {
    Class cls = NSClassFromString(name); if (cls) return cls;
    int count = objc_getClassList(NULL, 0); if (count <= 0) return Nil;
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class)); count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) if ([NSStringFromClass(classes[i]) isEqualToString:name]) { cls = classes[i]; break; }
    free(classes); return cls;
}

static uintptr_t CEAlpha28IsaMask(void) {
    static uintptr_t mask = 0; static dispatch_once_t once;
    dispatch_once(&once, ^{ uintptr_t *symbol = (uintptr_t *)dlsym(RTLD_DEFAULT, "objc_debug_isa_class_mask"); if (symbol) mask = *symbol; });
    return mask;
}

static NSSet<NSValue *> *CEAlpha28KnownClasses(void) {
    static NSSet<NSValue *> *known = nil; static dispatch_once_t once;
    dispatch_once(&once, ^{
        int count = objc_getClassList(NULL, 0); NSMutableSet<NSValue *> *values = [NSMutableSet setWithCapacity:MAX(count, 0)];
        if (count > 0) {
            Class *classes = (Class *)calloc((size_t)count, sizeof(Class)); count = objc_getClassList(classes, count);
            for (int i = 0; i < count; i++) [values addObject:[NSValue valueWithPointer:(__bridge const void *)classes[i]]];
            free(classes);
        }
        known = [values copy];
    });
    return known;
}

static BOOL CEAlpha28Validate(uintptr_t bits, Class expected, NSString **detail) {
    if (!bits || !expected || (bits & 7) != 0) { if (detail) *detail = @"missing/unaligned"; return NO; }
    void *ptr = (void *)bits; if (!malloc_zone_from_ptr(ptr)) { if (detail) *detail = @"not-malloc"; return NO; }
    size_t allocation = malloc_size(ptr), expectedSize = class_getInstanceSize(expected); uintptr_t isa = 0; memcpy(&isa, ptr, sizeof(isa)); uintptr_t mask = CEAlpha28IsaMask();
    BOOL matched = allocation >= expectedSize && (isa == (uintptr_t)expected || (mask && (isa & mask) == (uintptr_t)expected));
    if (detail) *detail = [NSString stringWithFormat:@"alloc=%zu expected=%zu isa=0x%llx mask=0x%llx match=%@", allocation, expectedSize, (unsigned long long)isa, (unsigned long long)mask, matched ? @"YES" : @"NO"];
    return matched;
}

static Class CEAlpha28ClassForHeapPointer(uintptr_t bits, size_t *allocationOut) {
    if (!bits || (bits & 7) != 0) return Nil;
    void *ptr = (void *)bits; if (!malloc_zone_from_ptr(ptr)) return Nil;
    size_t allocation = malloc_size(ptr); if (allocation < sizeof(uintptr_t) || allocation > 1024 * 1024) return Nil;
    uintptr_t isa = 0; memcpy(&isa, ptr, sizeof(isa)); uintptr_t mask = CEAlpha28IsaMask(); uintptr_t classBits = mask ? (isa & mask) : isa;
    if (!classBits || ![CEAlpha28KnownClasses() containsObject:[NSValue valueWithPointer:(const void *)classBits]]) return Nil;
    if (allocationOut) *allocationOut = allocation;
    return (__bridge Class)(const void *)classBits;
}

static NSString *CEAlpha28Bytes(void *object, Class cls, const char *name, size_t length) {
    if (!object || !cls) return @"<nil>"; Ivar ivar = class_getInstanceVariable(cls, name); if (!ivar) return @"<missing>";
    ptrdiff_t offset = ivar_getOffset(ivar); NSMutableString *hex = [NSMutableString string]; const uint8_t *raw = (const uint8_t *)object + offset;
    size_t available = class_getInstanceSize(cls) > (size_t)offset ? class_getInstanceSize(cls) - (size_t)offset : 0; length = MIN(length, available);
    for (size_t i = 0; i < length; i++) [hex appendFormat:@"%02x", raw[i]];
    return [NSString stringWithFormat:@"offset=0x%tx bytes=%@", offset, hex];
}

static UIViewController *CEAlpha28FindChild(UIViewController *vc, NSString *needle) {
    if (!vc) return nil;
    for (UIViewController *child in vc.childViewControllers) { if ([NSStringFromClass(child.class) containsString:needle]) return child; UIViewController *found = CEAlpha28FindChild(child, needle); if (found) return found; }
    return nil;
}

static BOOL CEAlpha28Contains(UIViewController *root, UIViewController *target) {
    if (!root || !target) return NO; if (root == target) return YES;
    for (UIViewController *child in root.childViewControllers) if (CEAlpha28Contains(child, target)) return YES;
    return NO;
}

static UINavigationController *CEAlpha28Nav(UIViewController *vc) {
    for (UIViewController *cursor = vc; cursor; cursor = cursor.parentViewController) if ([cursor isKindOfClass:UINavigationController.class]) return (UINavigationController *)cursor;
    return nil;
}

static NSString *CEAlpha28Methods(Class cls) {
    if (!cls) return @"<nil>";
    NSArray<NSString *> *needles = @[@"reload", @"refresh", @"resume", @"recover", @"fetch", @"load", @"update", @"apply", @"stream", @"state", @"conversation", @"message", @"item", @"repository", @"coordinator", @"did", @"will"];
    NSMutableArray<NSString *> *out = [NSMutableArray array]; unsigned int count = 0; Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count && out.count < 80; i++) { NSString *name = NSStringFromSelector(method_getName(methods[i])); NSString *lower = name.lowercaseString; for (NSString *needle in needles) if ([lower containsString:needle]) { [out addObject:[NSString stringWithFormat:@"-%@", name]]; break; } }
    free(methods);
    Class meta = object_getClass(cls); unsigned int classCount = 0; methods = class_copyMethodList(meta, &classCount);
    for (unsigned int i = 0; i < classCount && out.count < 100; i++) { NSString *name = NSStringFromSelector(method_getName(methods[i])); NSString *lower = name.lowercaseString; for (NSString *needle in needles) if ([lower containsString:needle]) { [out addObject:[NSString stringWithFormat:@"+%@", name]]; break; } }
    free(methods);
    return [NSString stringWithFormat:@"instance=%u class=%u relevant=%@", count, classCount, out.count ? [out componentsJoinedByString:@", "] : @"<none>"];
}

static BOOL CEAlpha28InterestingHeapClass(NSString *name) {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *needles = @[@"publisher", @"repository", @"coordinator", @"conversation", @"message", @"stream", @"state", @"api", @"service", @"provider", @"subject", @"reference", @"viewmodel"];
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static NSString *CEAlpha28HeapObjectPointers(void *object, size_t objectSize) {
    if (!object || !objectSize) return @"<nil>";
    NSMutableArray<NSString *> *hits = [NSMutableArray array]; size_t scanSize = MIN(objectSize, (size_t)8192);
    for (size_t offset = 0; offset + sizeof(uintptr_t) <= scanSize && hits.count < 80; offset += sizeof(uintptr_t)) {
        uintptr_t bits = 0; memcpy(&bits, (const uint8_t *)object + offset, sizeof(bits)); size_t allocation = 0; Class cls = CEAlpha28ClassForHeapPointer(bits, &allocation); if (!cls) continue;
        NSString *name = NSStringFromClass(cls); if (!CEAlpha28InterestingHeapClass(name)) continue;
        [hits addObject:[NSString stringWithFormat:@"0x%zx=0x%llx %@ alloc=%zu", offset, (unsigned long long)bits, name, allocation]];
    }
    return hits.count ? [hits componentsJoinedByString:@" | "] : @"<none>";
}

static void CEAlpha28Snapshot(NSString *reason) {
    UIViewController *messages = CEAlpha28ActiveMessages;
    if (!messages || !messages.viewIfLoaded.window) { CERecoveryDiagnosticLog(@"LIVE28", @"reason=%@ active=<nil/off-window>", reason); return; }
    CERecoveryDiagnosticMark(@"ALPHA28 LIVE ACTIVE CONVERSATION");
    CERecoveryDiagnosticLog(@"LIVE28", @"reason=%@ messages=%p parent=%@ context=%@", reason, messages, messages.parentViewController ? NSStringFromClass(messages.parentViewController.class) : @"<nil>", [CEConversationContext shared].conversationID ?: @"<nil>");
    UINavigationController *nav = CEAlpha28Nav(messages); NSMutableArray<NSString *> *routes = [NSMutableArray array];
    for (NSUInteger i = 0; i < nav.viewControllers.count; i++) { UIViewController *route = nav.viewControllers[i]; [routes addObject:[NSString stringWithFormat:@"%lu:%@%@%@", (unsigned long)i, NSStringFromClass(route.class), route == nav.topViewController ? @"[TOP]" : @"", CEAlpha28Contains(route, messages) ? @"[ACTIVE]" : @""]]; }
    CERecoveryDiagnosticLog(@"LIVE28-NAV", @"%@", routes.count ? [routes componentsJoinedByString:@" > "] : @"<nil>");
    CERecoveryDiagnosticLog(@"LIVE28-MSG", @"methods %@", CEAlpha28Methods(messages.class));

    Ivar vmIvar = class_getInstanceVariable(messages.class, "viewModel"); uintptr_t vmBits = 0; if (vmIvar) memcpy(&vmBits, (const uint8_t *)(__bridge const void *)messages + ivar_getOffset(vmIvar), sizeof(vmBits));
    Class vmClass = CEAlpha28Class(@"ChatGPTMessages.MessagesViewModel"); NSString *vmDetail = nil; BOOL vmOK = CEAlpha28Validate(vmBits, vmClass, &vmDetail);
    CERecoveryDiagnosticLog(@"LIVE28-VM", @"slot=0x%llx validation=%@ methods=%@", (unsigned long long)vmBits, vmDetail ?: @"<nil>", CEAlpha28Methods(vmClass));
    if (vmOK) {
        void *vm = (void *)vmBits;
        CERecoveryDiagnosticLog(@"LIVE28-VM", @"conversationCoordinator %@", CEAlpha28Bytes(vm, vmClass, "conversationCoordinator", 16));
        CERecoveryDiagnosticLog(@"LIVE28-VM", @"_conversationState %@", CEAlpha28Bytes(vm, vmClass, "_conversationState", 32));
        CERecoveryDiagnosticLog(@"LIVE28-VM", @"_coordinatorIsStreaming %@", CEAlpha28Bytes(vm, vmClass, "_coordinatorIsStreaming", 8));
        CERecoveryDiagnosticLog(@"LIVE28-VM-HEAP", @"%@", CEAlpha28HeapObjectPointers(vm, class_getInstanceSize(vmClass)));
        uintptr_t coordinatorBits = 0; Ivar coordinatorIvar = class_getInstanceVariable(vmClass, "conversationCoordinator"); if (coordinatorIvar) memcpy(&coordinatorBits, (const uint8_t *)vm + ivar_getOffset(coordinatorIvar), sizeof(coordinatorBits));
        Class coordinatorClass = CEAlpha28Class(@"Conversations.DefaultConversationCoordinator"); NSString *coordinatorDetail = nil; BOOL coordinatorOK = CEAlpha28Validate(coordinatorBits, coordinatorClass, &coordinatorDetail);
        CERecoveryDiagnosticLog(@"LIVE28-COORD", @"slot=0x%llx validation=%@ methods=%@", (unsigned long long)coordinatorBits, coordinatorDetail ?: @"<nil>", CEAlpha28Methods(coordinatorClass));
        if (coordinatorOK) {
            void *coordinator = (void *)coordinatorBits;
            CERecoveryDiagnosticLog(@"LIVE28-COORD", @"_state %@", CEAlpha28Bytes(coordinator, coordinatorClass, "_state", 40));
            CERecoveryDiagnosticLog(@"LIVE28-COORD", @"_serverStreamingStatus %@", CEAlpha28Bytes(coordinator, coordinatorClass, "_serverStreamingStatus", 40));
            CERecoveryDiagnosticLog(@"LIVE28-COORD", @"_remoteConversationId %@", CEAlpha28Bytes(coordinator, coordinatorClass, "_remoteConversationId", 40));
            CERecoveryDiagnosticLog(@"LIVE28-COORD", @"conversation %@", CEAlpha28Bytes(coordinator, coordinatorClass, "conversation", 96));
            CERecoveryDiagnosticLog(@"LIVE28-COORD", @"streamTask %@", CEAlpha28Bytes(coordinator, coordinatorClass, "streamTask", 8));
            CERecoveryDiagnosticLog(@"LIVE28-COORD", @"eventSourceMessageStreamEnabled %@", CEAlpha28Bytes(coordinator, coordinatorClass, "eventSourceMessageStreamEnabled", 1));
            CERecoveryDiagnosticLog(@"LIVE28-COORD-HEAP", @"%@", CEAlpha28HeapObjectPointers(coordinator, class_getInstanceSize(coordinatorClass)));
        }
    }
    UIViewController *collection = CEAlpha28FindChild(messages, @"ChatCollectionViewController");
    CERecoveryDiagnosticLog(@"LIVE28-COLLECTION", @"controller=%p class=%@ methods=%@", collection, collection ? NSStringFromClass(collection.class) : @"<nil>", collection ? CEAlpha28Methods(collection.class) : @"<nil>");
}

static void CEAlpha28DidAppear(id self, SEL _cmd, BOOL animated) {
    if (CEAlpha28PriorDidAppear) ((void (*)(id, SEL, BOOL))CEAlpha28PriorDidAppear)(self, _cmd, animated);
    CEAlpha28ActiveMessages = (UIViewController *)self; CERecoveryDiagnosticLog(@"LIVE28-LIFECYCLE", @"active=%p", self);
    __weak UIViewController *weakSelf = self; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (weakSelf && CEAlpha28ActiveMessages == weakSelf) CEAlpha28Snapshot(@"viewDidAppear"); });
}

static void CEAlpha28DidDisappear(id self, SEL _cmd, BOOL animated) {
    if (CEAlpha28PriorDidDisappear) ((void (*)(id, SEL, BOOL))CEAlpha28PriorDidDisappear)(self, _cmd, animated);
    if (CEAlpha28ActiveMessages == self) CEAlpha28ActiveMessages = nil;
}

static void CEAlpha28Install(NSUInteger attempt) {
    static BOOL installed = NO; if (installed) return; Class cls = CEAlpha28Class(@"ChatGPTMessages.MessagesViewController");
    if (!cls) { if (attempt < 30) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEAlpha28Install(attempt + 1); }); return; }
    Method appeared = class_getInstanceMethod(cls, @selector(viewDidAppear:)), disappeared = class_getInstanceMethod(cls, @selector(viewDidDisappear:)); if (!appeared || !disappeared) return;
    CEAlpha28PriorDidAppear = method_getImplementation(appeared); CEAlpha28PriorDidDisappear = method_getImplementation(disappeared); method_setImplementation(appeared, (IMP)CEAlpha28DidAppear); method_setImplementation(disappeared, (IMP)CEAlpha28DidDisappear); installed = YES;
    CERecoveryDiagnosticLog(@"LIVE28-HOOK", @"installed class=%@", NSStringFromClass(cls));
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (CEAlpha28ActiveMessages) CEAlpha28Snapshot(@"foreground"); }); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:CEConversationContextDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (CEAlpha28ActiveMessages) CEAlpha28Snapshot(@"contextChanged"); }); }];
}

__attribute__((constructor)) static void CEAlpha28Entry(void) {
    @autoreleasepool { if (!CETargetApp()) return; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEAlpha28Install(0); }); }
}
