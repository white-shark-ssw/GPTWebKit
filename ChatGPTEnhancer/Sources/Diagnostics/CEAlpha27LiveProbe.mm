#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <dlfcn.h>
#import "../Core/CECore.h"
#import "CERecoveryDiagnostics.h"

static __weak UIViewController *CEAlpha27ActiveMessages = nil;
static IMP CEAlpha27PriorDidAppear = NULL;
static IMP CEAlpha27PriorDidDisappear = NULL;

static Class CEAlpha27Class(NSString *name) {
    Class cls = NSClassFromString(name); if (cls) return cls;
    int count = objc_getClassList(NULL, 0); if (count <= 0) return Nil;
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class)); count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) if ([NSStringFromClass(classes[i]) isEqualToString:name]) { cls = classes[i]; break; }
    free(classes); return cls;
}

static uintptr_t CEAlpha27IsaMask(void) {
    static uintptr_t mask = 0; static dispatch_once_t once;
    dispatch_once(&once, ^{ uintptr_t *symbol = (uintptr_t *)dlsym(RTLD_DEFAULT, "objc_debug_isa_class_mask"); if (symbol) mask = *symbol; });
    return mask;
}

static BOOL CEAlpha27Validate(uintptr_t bits, Class expected, NSString **detail) {
    if (!bits || !expected || (bits & 7) != 0) { if (detail) *detail = @"missing/unaligned"; return NO; }
    void *ptr = (void *)bits; if (!malloc_zone_from_ptr(ptr)) { if (detail) *detail = @"not-malloc"; return NO; }
    size_t allocation = malloc_size(ptr), expectedSize = class_getInstanceSize(expected); uintptr_t isa = 0; memcpy(&isa, ptr, sizeof(isa)); uintptr_t mask = CEAlpha27IsaMask();
    BOOL matched = allocation >= expectedSize && (isa == (uintptr_t)expected || (mask && (isa & mask) == (uintptr_t)expected));
    if (detail) *detail = [NSString stringWithFormat:@"alloc=%zu expected=%zu isa=0x%llx mask=0x%llx match=%@", allocation, expectedSize, (unsigned long long)isa, (unsigned long long)mask, matched ? @"YES" : @"NO"];
    return matched;
}

static NSString *CEAlpha27Bytes(void *object, Class cls, const char *name, size_t length) {
    if (!object || !cls) return @"<nil>"; Ivar ivar = class_getInstanceVariable(cls, name); if (!ivar) return @"<missing>";
    ptrdiff_t offset = ivar_getOffset(ivar); NSMutableString *hex = [NSMutableString string]; const uint8_t *raw = (const uint8_t *)object + offset;
    for (size_t i = 0; i < length; i++) [hex appendFormat:@"%02x", raw[i]];
    return [NSString stringWithFormat:@"offset=0x%tx bytes=%@", offset, hex];
}

static UIViewController *CEAlpha27FindChild(UIViewController *vc, NSString *needle) {
    if (!vc) return nil;
    for (UIViewController *child in vc.childViewControllers) { if ([NSStringFromClass(child.class) containsString:needle]) return child; UIViewController *found = CEAlpha27FindChild(child, needle); if (found) return found; }
    return nil;
}

static BOOL CEAlpha27Contains(UIViewController *root, UIViewController *target) {
    if (!root || !target) return NO; if (root == target) return YES;
    for (UIViewController *child in root.childViewControllers) if (CEAlpha27Contains(child, target)) return YES;
    return NO;
}

static UINavigationController *CEAlpha27Nav(UIViewController *vc) {
    for (UIViewController *cursor = vc; cursor; cursor = cursor.parentViewController) if ([cursor isKindOfClass:UINavigationController.class]) return (UINavigationController *)cursor;
    return nil;
}

static NSString *CEAlpha27Methods(Class cls) {
    if (!cls) return @"<nil>"; unsigned int count = 0; Method *methods = class_copyMethodList(cls, &count); NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSString *> *needles = @[@"reload", @"refresh", @"resume", @"recover", @"fetch", @"load", @"update", @"apply", @"stream", @"state", @"conversation", @"message", @"item"];
    for (unsigned int i = 0; i < count && out.count < 40; i++) { NSString *name = NSStringFromSelector(method_getName(methods[i])); NSString *lower = name.lowercaseString; for (NSString *needle in needles) if ([lower containsString:needle]) { [out addObject:name]; break; } }
    free(methods); return [NSString stringWithFormat:@"count=%u relevant=%@", count, out.count ? [out componentsJoinedByString:@", "] : @"<none>"];
}

static void CEAlpha27Snapshot(NSString *reason) {
    UIViewController *messages = CEAlpha27ActiveMessages;
    if (!messages || !messages.viewIfLoaded.window) { CERecoveryDiagnosticLog(@"LIVE27", @"reason=%@ active=<nil/off-window>", reason); return; }
    CERecoveryDiagnosticMark(@"ALPHA27 LIVE ACTIVE CONVERSATION");
    CERecoveryDiagnosticLog(@"LIVE27", @"reason=%@ messages=%p parent=%@ context=%@", reason, messages, messages.parentViewController ? NSStringFromClass(messages.parentViewController.class) : @"<nil>", [CEConversationContext shared].conversationID ?: @"<nil>");
    UINavigationController *nav = CEAlpha27Nav(messages); NSMutableArray<NSString *> *routes = [NSMutableArray array];
    for (NSUInteger i = 0; i < nav.viewControllers.count; i++) { UIViewController *route = nav.viewControllers[i]; [routes addObject:[NSString stringWithFormat:@"%lu:%@%@%@", (unsigned long)i, NSStringFromClass(route.class), route == nav.topViewController ? @"[TOP]" : @"", CEAlpha27Contains(route, messages) ? @"[ACTIVE]" : @""]]; }
    CERecoveryDiagnosticLog(@"LIVE27-NAV", @"%@", routes.count ? [routes componentsJoinedByString:@" > "] : @"<nil>");

    Ivar vmIvar = class_getInstanceVariable(messages.class, "viewModel"); uintptr_t vmBits = 0; if (vmIvar) memcpy(&vmBits, (const uint8_t *)(__bridge const void *)messages + ivar_getOffset(vmIvar), sizeof(vmBits));
    Class vmClass = CEAlpha27Class(@"ChatGPTMessages.MessagesViewModel"); NSString *vmDetail = nil; BOOL vmOK = CEAlpha27Validate(vmBits, vmClass, &vmDetail);
    CERecoveryDiagnosticLog(@"LIVE27-VM", @"slot=0x%llx validation=%@", (unsigned long long)vmBits, vmDetail ?: @"<nil>");
    if (vmOK) {
        void *vm = (void *)vmBits;
        CERecoveryDiagnosticLog(@"LIVE27-VM", @"conversationCoordinator %@", CEAlpha27Bytes(vm, vmClass, "conversationCoordinator", 16));
        CERecoveryDiagnosticLog(@"LIVE27-VM", @"_conversationState %@", CEAlpha27Bytes(vm, vmClass, "_conversationState", 32));
        CERecoveryDiagnosticLog(@"LIVE27-VM", @"_coordinatorIsStreaming %@", CEAlpha27Bytes(vm, vmClass, "_coordinatorIsStreaming", 8));
        uintptr_t coordinatorBits = 0; Ivar coordinatorIvar = class_getInstanceVariable(vmClass, "conversationCoordinator"); if (coordinatorIvar) memcpy(&coordinatorBits, (const uint8_t *)vm + ivar_getOffset(coordinatorIvar), sizeof(coordinatorBits));
        Class coordinatorClass = CEAlpha27Class(@"Conversations.DefaultConversationCoordinator"); NSString *coordinatorDetail = nil; BOOL coordinatorOK = CEAlpha27Validate(coordinatorBits, coordinatorClass, &coordinatorDetail);
        CERecoveryDiagnosticLog(@"LIVE27-COORD", @"slot=0x%llx validation=%@", (unsigned long long)coordinatorBits, coordinatorDetail ?: @"<nil>");
        if (coordinatorOK) {
            void *coordinator = (void *)coordinatorBits;
            CERecoveryDiagnosticLog(@"LIVE27-COORD", @"_state %@", CEAlpha27Bytes(coordinator, coordinatorClass, "_state", 32));
            CERecoveryDiagnosticLog(@"LIVE27-COORD", @"_serverStreamingStatus %@", CEAlpha27Bytes(coordinator, coordinatorClass, "_serverStreamingStatus", 32));
            CERecoveryDiagnosticLog(@"LIVE27-COORD", @"_remoteConversationId %@", CEAlpha27Bytes(coordinator, coordinatorClass, "_remoteConversationId", 32));
            CERecoveryDiagnosticLog(@"LIVE27-COORD", @"streamTask %@", CEAlpha27Bytes(coordinator, coordinatorClass, "streamTask", 8));
            CERecoveryDiagnosticLog(@"LIVE27-COORD", @"eventSourceMessageStreamEnabled %@", CEAlpha27Bytes(coordinator, coordinatorClass, "eventSourceMessageStreamEnabled", 1));
            CERecoveryDiagnosticLog(@"LIVE27-COORD", @"methods %@", CEAlpha27Methods(coordinatorClass));
        }
    }
    UIViewController *collection = CEAlpha27FindChild(messages, @"ChatCollectionViewController");
    CERecoveryDiagnosticLog(@"LIVE27-COLLECTION", @"controller=%p class=%@ methods=%@", collection, collection ? NSStringFromClass(collection.class) : @"<nil>", collection ? CEAlpha27Methods(collection.class) : @"<nil>");
}

static void CEAlpha27DidAppear(id self, SEL _cmd, BOOL animated) {
    if (CEAlpha27PriorDidAppear) ((void (*)(id, SEL, BOOL))CEAlpha27PriorDidAppear)(self, _cmd, animated);
    CEAlpha27ActiveMessages = (UIViewController *)self; CERecoveryDiagnosticLog(@"LIVE27-LIFECYCLE", @"active=%p", self);
    __weak UIViewController *weakSelf = self; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (weakSelf && CEAlpha27ActiveMessages == weakSelf) CEAlpha27Snapshot(@"viewDidAppear"); });
}

static void CEAlpha27DidDisappear(id self, SEL _cmd, BOOL animated) {
    if (CEAlpha27PriorDidDisappear) ((void (*)(id, SEL, BOOL))CEAlpha27PriorDidDisappear)(self, _cmd, animated);
    if (CEAlpha27ActiveMessages == self) CEAlpha27ActiveMessages = nil;
}

static void CEAlpha27Install(NSUInteger attempt) {
    static BOOL installed = NO; if (installed) return; Class cls = CEAlpha27Class(@"ChatGPTMessages.MessagesViewController");
    if (!cls) { if (attempt < 30) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEAlpha27Install(attempt + 1); }); return; }
    Method appeared = class_getInstanceMethod(cls, @selector(viewDidAppear:)), disappeared = class_getInstanceMethod(cls, @selector(viewDidDisappear:)); if (!appeared || !disappeared) return;
    CEAlpha27PriorDidAppear = method_getImplementation(appeared); CEAlpha27PriorDidDisappear = method_getImplementation(disappeared); method_setImplementation(appeared, (IMP)CEAlpha27DidAppear); method_setImplementation(disappeared, (IMP)CEAlpha27DidDisappear); installed = YES;
    CERecoveryDiagnosticLog(@"LIVE27-HOOK", @"installed class=%@", NSStringFromClass(cls));
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (CEAlpha27ActiveMessages) CEAlpha27Snapshot(@"foreground"); }); }];
}

__attribute__((constructor)) static void CEAlpha27Entry(void) {
    @autoreleasepool { if (!CETargetApp()) return; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEAlpha27Install(0); }); }
}
