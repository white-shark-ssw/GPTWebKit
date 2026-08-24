#import "CEDiagnostics.h"
#import "CERecoveryDiagnostics.h"
#import "../Features/CEForegroundStreamRecovery.h"
#import "../Features/CEOrphanedConversationRecovery.h"
#import "../Core/CECore.h"
#import "../Network/CENetworkObserver.h"
#import "../Storage/CECatalog.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static void CEAppendAccessibilityValue(NSMutableOrderedSet<NSString *> *out, id object) {
    if (!object || out.count >= 400) return;
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

static void CECollectAccessibility(UIView *view, NSUInteger depth, NSMutableOrderedSet<NSString *> *out) {
    if (!view || depth > 14 || out.count >= 400) return;
    CEAppendAccessibilityValue(out, view);
    NSArray *elements = nil; @try { elements = view.accessibilityElements; } @catch (__unused NSException *exception) {}
    for (id element in elements ?: @[]) CEAppendAccessibilityValue(out, element);
    for (UIView *child in view.subviews) CECollectAccessibility(child, depth + 1, out);
}

static NSString *CEViewChain(UIView *view) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    UIView *cursor = view;
    for (NSUInteger i = 0; cursor && i < 12; i++, cursor = cursor.superview) {
        NSString *identifier = cursor.accessibilityIdentifier ?: @"";
        NSString *label = cursor.accessibilityLabel ?: @"";
        NSString *value = cursor.accessibilityValue ?: @"";
        [lines addObject:[NSString stringWithFormat:@"%lu. %@ id=%@ label=%@ value=%@", (unsigned long)i, NSStringFromClass(cursor.class), identifier, label, value]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

static void CEAppendViewControllerTree(UIViewController *vc, NSUInteger depth, NSMutableArray<NSString *> *lines) {
    if (!vc || depth > 10 || lines.count > 80) return;
    [lines addObject:[NSString stringWithFormat:@"%@%@", [@"  " stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0], NSStringFromClass(vc.class)]];
    if (vc.presentedViewController) CEAppendViewControllerTree(vc.presentedViewController, depth + 1, lines);
    for (UIViewController *child in vc.childViewControllers) CEAppendViewControllerTree(child, depth + 1, lines);
}

static NSArray<NSString *> *CEDatabaseCandidates(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSString *> *roots = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]
    ];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) { return YES; }];
        for (NSURL *url in enumerator) {
            if (out.count >= 80) break;
            NSString *name = url.lastPathComponent.lowercaseString;
            NSString *ext = url.pathExtension.lowercaseString;
            BOOL looksDB = [@[@"db", @"sqlite", @"sqlite3"] containsObject:ext] || [name containsString:@"sqlite"] || [name containsString:@"database"];
            if (!looksDB) continue;
            NSNumber *size = nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            NSString *relative = [url.path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
            [out addObject:[NSString stringWithFormat:@"%@ (%@ bytes)", relative, size ?: @0]];
        }
    }
    return out;
}

static NSArray<NSString *> *CEInterestingRuntimeClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSArray<NSString *> *needles = @[@"conversation", @"message", @"project", @"thread", @"sidebar", @"history", @"chat", @"network", @"api", @"gpt"];
    for (int i = 0; i < count && out.count < 180; i++) {
        Class cls = classes[i];
        const char *rawName = class_getName(cls); const char *rawImage = class_getImageName(cls);
        if (!rawName || !rawImage) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        NSString *image = [NSString stringWithUTF8String:rawImage];
        if (bundlePath.length && ![image hasPrefix:bundlePath]) continue;
        NSString *lower = name.lowercaseString;
        BOOL match = NO; for (NSString *needle in needles) if ([lower containsString:needle]) { match = YES; break; }
        if (match) [out addObject:[NSString stringWithFormat:@"%@ | %@", name, image.lastPathComponent]];
    }
    free(classes);
    return [out sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSArray<NSString *> *CERuntimeDetails(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (int i = 0; i < count && out.count < 220; i++) {
        Class cls = classes[i];
        const char *rawName = class_getName(cls); if (!rawName) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        NSString *lower = name.lowercaseString;
        BOOL target = [lower containsString:@"oaiapi"] || [lower containsString:@"conversationfinalstream"] || [lower containsString:@"conversationcoordinator"] || [lower containsString:@"conversationsrepository"];
        if (!target) continue;
        [out addObject:[NSString stringWithFormat:@"CLASS %@", name]];

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int m = 0; m < methodCount && m < 40 && out.count < 220; m++) {
            SEL sel = method_getName(methods[m]);
            const char *types = method_getTypeEncoding(methods[m]);
            [out addObject:[NSString stringWithFormat:@"  - %@ | %s", NSStringFromSelector(sel), types ?: ""]];
        }
        free(methods);

        Class meta = object_getClass(cls);
        methodCount = 0; methods = class_copyMethodList(meta, &methodCount);
        for (unsigned int m = 0; m < methodCount && m < 24 && out.count < 220; m++) {
            SEL sel = method_getName(methods[m]); const char *types = method_getTypeEncoding(methods[m]);
            [out addObject:[NSString stringWithFormat:@"  + %@ | %s", NSStringFromSelector(sel), types ?: ""]];
        }
        free(methods);

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        for (unsigned int v = 0; v < ivarCount && v < 32 && out.count < 220; v++) {
            const char *n = ivar_getName(ivars[v]); const char *t = ivar_getTypeEncoding(ivars[v]);
            [out addObject:[NSString stringWithFormat:@"  ivar %s | %s", n ?: "", t ?: ""]];
        }
        free(ivars);
    }
    free(classes);
    return out;
}


static NSString *CECompactObjectDescription(id object) {
    if (!object) return @"<nil>";
    NSString *value = nil;
    @try { value = [object description]; } @catch (__unused NSException *exception) {}
    if (!value.length) value = [NSString stringWithFormat:@"<%@>", NSStringFromClass([object class])];
    value = [value stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (value.length > 360) value = [[value substringToIndex:360] stringByAppendingString:@"…"];
    return value;
}

static UIViewController *CEFindViewControllerContainingClassName(UIViewController *vc, NSString *needle, NSUInteger depth) {
    if (!vc || !needle.length || depth > 16) return nil;
    if ([NSStringFromClass(vc.class) containsString:needle]) return vc;
    if (vc.presentedViewController) {
        UIViewController *found = CEFindViewControllerContainingClassName(vc.presentedViewController, needle, depth + 1);
        if (found) return found;
    }
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *found = CEFindViewControllerContainingClassName(child, needle, depth + 1);
        if (found) return found;
    }
    return nil;
}

static BOOL CESelectorLooksRelevant(NSString *name) {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *needles = @[@"conversation", @"message", @"coordinator", @"reload", @"refresh", @"resume", @"recover", @"load", @"update", @"state", @"viewmodel", @"repository", @"configure", @"navigation", @"route", @"appear", @"stream", @"fetch"];
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static void CEAppendRuntimeClassDetails(NSMutableArray<NSString *> *out, Class cls, id object, NSString *label) {
    if (!cls || out.count > 420) return;
    [out addObject:[NSString stringWithFormat:@"%@ class=%@ ptr=%p instanceSize=%zu", label ?: @"object", NSStringFromClass(cls), object, class_getInstanceSize(cls)]];
    Class cursor = cls;
    for (NSUInteger depth = 0; cursor && depth < 5 && out.count < 420; depth++, cursor = class_getSuperclass(cursor)) {
        [out addObject:[NSString stringWithFormat:@"  CLASS[%lu] %@ size=%zu", (unsigned long)depth, NSStringFromClass(cursor), class_getInstanceSize(cursor)]];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cursor, &methodCount);
        NSUInteger emittedMethods = 0;
        for (unsigned int i = 0; i < methodCount && emittedMethods < 90 && out.count < 420; i++) {
            NSString *selName = NSStringFromSelector(method_getName(methods[i]));
            if (!CESelectorLooksRelevant(selName) && methodCount > 40) continue;
            const char *types = method_getTypeEncoding(methods[i]);
            [out addObject:[NSString stringWithFormat:@"    - %@ | %s", selName, types ?: ""]];
            emittedMethods++;
        }
        free(methods);

        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(cursor, &propertyCount);
        for (unsigned int i = 0; i < propertyCount && i < 64 && out.count < 420; i++) {
            const char *name = property_getName(properties[i]); const char *attrs = property_getAttributes(properties[i]);
            [out addObject:[NSString stringWithFormat:@"    property %s | %s", name ?: "", attrs ?: ""]];
        }
        free(properties);

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cursor, &ivarCount);
        for (unsigned int i = 0; i < ivarCount && i < 64 && out.count < 420; i++) {
            Ivar ivar = ivars[i];
            const char *name = ivar_getName(ivar); const char *type = ivar_getTypeEncoding(ivar);
            ptrdiff_t offset = ivar_getOffset(ivar);
            NSString *suffix = @"";
            if (object && type && type[0] == '@') {
                id value = nil;
                @try { value = object_getIvar(object, ivar); } @catch (__unused NSException *exception) {}
                if (value) suffix = [NSString stringWithFormat:@" valueClass=%@ value=%@", NSStringFromClass([value class]), CECompactObjectDescription(value)];
            }
            [out addObject:[NSString stringWithFormat:@"    ivar %s | %s offset=0x%tx%@", name ?: "", type ?: "", offset, suffix]];
        }
        free(ivars);
    }
}

static NSArray<NSString *> *CENavigationRouterClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSArray<NSString *> *needles = @[@"router", @"route", @"deeplink", @"navigationdestination", @"conversationroot", @"sidemenu"];
    for (int i = 0; i < count && out.count < 120; i++) {
        Class cls = classes[i]; const char *rawName = class_getName(cls); const char *rawImage = class_getImageName(cls);
        if (!rawName || !rawImage) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        NSString *image = [NSString stringWithUTF8String:rawImage];
        if (bundlePath.length && ![image hasPrefix:bundlePath]) continue;
        NSString *lower = name.lowercaseString; BOOL match = NO;
        for (NSString *needle in needles) if ([lower containsString:needle]) { match = YES; break; }
        if (match) [out addObject:[NSString stringWithFormat:@"%@ | %@", name, image.lastPathComponent]];
    }
    free(classes);
    return [out sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSArray<NSString *> *CEActiveConversationRuntimeDetails(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    UIWindow *window = CEKeyWindow();
    UIViewController *root = window.rootViewController;
    UIViewController *messages = CEFindViewControllerContainingClassName(root, @"ChatGPTMessages.MessagesViewController", 0);
    UIViewController *collection = messages ? CEFindViewControllerContainingClassName(messages, @"ChatCollectionViewController", 0) : nil;
    [out addObject:[NSString stringWithFormat:@"window=%@ root=%@ messages=%@ ptr=%p collectionVC=%@ ptr=%p", window ? NSStringFromClass(window.class) : @"<nil>", root ? NSStringFromClass(root.class) : @"<nil>", messages ? NSStringFromClass(messages.class) : @"<nil>", messages, collection ? NSStringFromClass(collection.class) : @"<nil>", collection]];
    if (messages) {
        NSMutableArray<NSString *> *parents = [NSMutableArray array];
        UIViewController *cursor = messages;
        for (NSUInteger i = 0; cursor && i < 10; i++, cursor = cursor.parentViewController) [parents addObject:[NSString stringWithFormat:@"%lu:%@[%p]", (unsigned long)i, NSStringFromClass(cursor.class), cursor]];
        [out addObject:[NSString stringWithFormat:@"messagesParentChain=%@", [parents componentsJoinedByString:@" > "]]];
        CEAppendRuntimeClassDetails(out, messages.class, messages, @"MESSAGES");
    }
    if (collection) CEAppendRuntimeClassDetails(out, collection.class, collection, @"COLLECTION");
    NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
    [out addObject:[NSString stringWithFormat:@"CFBundleURLTypes=%@", info[@"CFBundleURLTypes"] ?: @"<nil>"]];
    [out addObject:[NSString stringWithFormat:@"UIApplicationQueriesSchemes=%@", info[@"LSApplicationQueriesSchemes"] ?: @"<nil>"]];
    return out;
}

static IMP CEMessagesOriginalViewDidLoad = NULL;
static IMP CEMessagesOriginalViewWillAppear = NULL;
static IMP CEMessagesOriginalViewDidAppear = NULL;
static IMP CEMessagesOriginalViewWillDisappear = NULL;
static IMP CEMessagesOriginalViewDidDisappear = NULL;

static void CEMessagesDiagViewDidLoad(id self, SEL _cmd) {
    if (CEMessagesOriginalViewDidLoad) ((void (*)(id, SEL))CEMessagesOriginalViewDidLoad)(self, _cmd);
    CERecoveryDiagnosticLog(@"MSG-LIFECYCLE", @"viewDidLoad self=%p class=%@ parent=%@ context=%@", self, NSStringFromClass([self class]), [self parentViewController] ? NSStringFromClass([[self parentViewController] class]) : @"<nil>", [CEConversationContext shared].conversationID ?: @"<nil>");
}
static void CEMessagesDiagViewWillAppear(id self, SEL _cmd, BOOL animated) {
    CERecoveryDiagnosticLog(@"MSG-LIFECYCLE", @"viewWillAppear self=%p animated=%@ context=%@", self, animated ? @"YES" : @"NO", [CEConversationContext shared].conversationID ?: @"<nil>");
    if (CEMessagesOriginalViewWillAppear) ((void (*)(id, SEL, BOOL))CEMessagesOriginalViewWillAppear)(self, _cmd, animated);
}
static void CEMessagesDiagViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (CEMessagesOriginalViewDidAppear) ((void (*)(id, SEL, BOOL))CEMessagesOriginalViewDidAppear)(self, _cmd, animated);
    CERecoveryDiagnosticLog(@"MSG-LIFECYCLE", @"viewDidAppear self=%p animated=%@ context=%@", self, animated ? @"YES" : @"NO", [CEConversationContext shared].conversationID ?: @"<nil>");
}
static void CEMessagesDiagViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    CERecoveryDiagnosticLog(@"MSG-LIFECYCLE", @"viewWillDisappear self=%p animated=%@ context=%@", self, animated ? @"YES" : @"NO", [CEConversationContext shared].conversationID ?: @"<nil>");
    if (CEMessagesOriginalViewWillDisappear) ((void (*)(id, SEL, BOOL))CEMessagesOriginalViewWillDisappear)(self, _cmd, animated);
}
static void CEMessagesDiagViewDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (CEMessagesOriginalViewDidDisappear) ((void (*)(id, SEL, BOOL))CEMessagesOriginalViewDidDisappear)(self, _cmd, animated);
    CERecoveryDiagnosticLog(@"MSG-LIFECYCLE", @"viewDidDisappear self=%p animated=%@ context=%@", self, animated ? @"YES" : @"NO", [CEConversationContext shared].conversationID ?: @"<nil>");
}

static BOOL CEInstallMessagesLifecycleMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return NO;
    IMP original = method_getImplementation(inherited); const char *types = method_getTypeEncoding(inherited);
    if (originalOut) *originalOut = original;
    if (class_addMethod(cls, selector, replacement, types)) return YES;
    Method local = class_getInstanceMethod(cls, selector);
    if (!local) return NO;
    method_setImplementation(local, replacement);
    return YES;
}

static void CEInstallActiveConversationDiagnosticsAttempt(NSUInteger attempt) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = NSClassFromString(@"ChatGPTMessages.MessagesViewController");
    if (!cls) {
        if (attempt < 30) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEInstallActiveConversationDiagnosticsAttempt(attempt + 1); });
        return;
    }
    BOOL ok = YES;
    ok &= CEInstallMessagesLifecycleMethod(cls, @selector(viewDidLoad), (IMP)CEMessagesDiagViewDidLoad, &CEMessagesOriginalViewDidLoad);
    ok &= CEInstallMessagesLifecycleMethod(cls, @selector(viewWillAppear:), (IMP)CEMessagesDiagViewWillAppear, &CEMessagesOriginalViewWillAppear);
    ok &= CEInstallMessagesLifecycleMethod(cls, @selector(viewDidAppear:), (IMP)CEMessagesDiagViewDidAppear, &CEMessagesOriginalViewDidAppear);
    ok &= CEInstallMessagesLifecycleMethod(cls, @selector(viewWillDisappear:), (IMP)CEMessagesDiagViewWillDisappear, &CEMessagesOriginalViewWillDisappear);
    ok &= CEInstallMessagesLifecycleMethod(cls, @selector(viewDidDisappear:), (IMP)CEMessagesDiagViewDidDisappear, &CEMessagesOriginalViewDidDisappear);
    installed = ok;
    CERecoveryDiagnosticLog(@"MSG-HOOK", @"installed=%@ class=%@", ok ? @"YES" : @"NO", NSStringFromClass(cls));
}

void CEInstallActiveConversationDiagnostics(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ CEInstallActiveConversationDiagnosticsAttempt(0); });
}

static NSArray<NSString *> *CEBundledImages(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count && out.count < 120; i++) {
        const char *raw = _dyld_get_image_name(i); if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw];
        if (bundlePath.length && [path hasPrefix:bundlePath]) [out addObject:path.lastPathComponent];
    }
    return [out sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSString *CESafeCatalogStats(void) {
    @try {
        id catalog = [CECatalog shared];
        NSDictionary *byID = [catalog valueForKey:@"byID"];
        NSDictionary *full = [catalog valueForKey:@"fullDataByID"];
        return [NSString stringWithFormat:@"records=%lu cachedFull=%lu", (unsigned long)([byID isKindOfClass:NSDictionary.class] ? byID.count : 0), (unsigned long)([full isKindOfClass:NSDictionary.class] ? full.count : 0)];
    } @catch (__unused NSException *exception) { return @"unavailable"; }
}

NSString *CEDiagnosticsReport(UIView *sourceView, NSString *contextIdentifier) {
    NSMutableString *report = [NSMutableString string];
    NSBundle *bundle = NSBundle.mainBundle;
    CEConversationContext *ctx = [CEConversationContext shared];
    CENetworkObserver *observer = [CENetworkObserver shared];
    NSURLRequest *request = observer.requestTemplate;
    NSURLSession *session = observer.requestSession;

    [report appendFormat:@"ChatGPTEnhancer diagnostics\nversion=%@\napp=%@ %@\nbundle=%@\niOS=%@\n\n", CEVersion, [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?", [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?", bundle.bundleIdentifier ?: @"?", UIDevice.currentDevice.systemVersion];
    [report appendFormat:@"[Context]\nconversationID=%@\ntitle=%@\ncontextMenuIdentifier=%@\ncontextUpdatedAt=%@\ncontextAge=%.3fs\nappState=%ld\n\n", ctx.conversationID ?: @"<nil>", ctx.title ?: @"<nil>", contextIdentifier ?: @"<nil>", ctx.updatedAt ?: (id)@"<nil>", ctx.updatedAt ? [NSDate.date timeIntervalSinceDate:ctx.updatedAt] : -1.0, (long)UIApplication.sharedApplication.applicationState];

    [report appendFormat:@"[Foreground stream recovery live state]\n%@\n\n", CEForegroundStreamRecoveryDiagnosticsSnapshot()];
    [report appendFormat:@"[Full reload live state]\n%@\n\n", CEOrphanedConversationRecoveryDiagnosticsSnapshot()];
    [report appendFormat:@"[Recovery event journal]\n%@\n\n", CERecoveryDiagnosticsReport()];

    NSArray *headerKeys = [[request.allHTTPHeaderFields allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSDictionary *additional = session.configuration.HTTPAdditionalHeaders;
    NSArray *additionalKeys = [[additional allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *protocols = [NSMutableArray array]; for (Class cls in session.configuration.protocolClasses ?: @[]) [protocols addObject:NSStringFromClass(cls)];
    [report appendFormat:@"[Network]\nhasUsableTemplate=%@\ntemplateScore=%ld\ntemplateMethod=%@\ntemplateURL=%@\nheaderKeys=%@\nrequestSession=%@\nsessionIdentifier=%@\nHTTPAdditionalHeaderKeys=%@\nprotocolClasses=%@\nbaseOrigin=%@\n\n", observer.hasUsableTemplate ? @"YES" : @"NO", (long)observer.templateScore, request.HTTPMethod ?: @"<nil>", request.URL.absoluteString ?: @"<nil>", headerKeys ?: @[], session ? NSStringFromClass(session.class) : @"<nil>", session.configuration.identifier ?: @"<nil>", additionalKeys ?: @[], protocols, observer.baseOrigin ?: @"<nil>"];

    [report appendString:@"[Recent network events]\n"];
    for (NSString *event in observer.recentEvents) [report appendFormat:@"%@\n", event];
    [report appendString:@"\n"];

    [report appendFormat:@"[Catalog]\n%@\nknownProjectIDs=%lu\n\n", CESafeCatalogStats(), (unsigned long)observer.knownProjectIDs.count];

    UIWindow *window = CEKeyWindow();
    NSMutableOrderedSet<NSString *> *accessibility = [NSMutableOrderedSet orderedSet];
    CECollectAccessibility(window, 0, accessibility);
    NSArray<NSString *> *visible = window ? CECollectVisibleStrings(window, 12) : @[];
    [report appendString:@"[Accessibility strings]\n"];
    NSUInteger aCount = MIN((NSUInteger)120, accessibility.count); for (NSUInteger i = 0; i < aCount; i++) [report appendFormat:@"A%03lu: %@\n", (unsigned long)i, accessibility[i]];
    [report appendString:@"\n[Visible strings]\n"];
    NSUInteger vCount = MIN((NSUInteger)120, visible.count); for (NSUInteger i = 0; i < vCount; i++) [report appendFormat:@"V%03lu: %@\n", (unsigned long)i, visible[i]];

    [report appendFormat:@"\n[Source view chain]\n%@\n", sourceView ? CEViewChain(sourceView) : @"<nil>"];
    NSMutableArray<NSString *> *vcLines = [NSMutableArray array]; CEAppendViewControllerTree(window.rootViewController, 0, vcLines);
    [report appendFormat:@"\n[View controllers]\n%@\n", [vcLines componentsJoinedByString:@"\n"]];

    [report appendString:@"\n[Active conversation runtime]\n"];
    for (NSString *line in CEActiveConversationRuntimeDetails()) [report appendFormat:@"%@\n", line];
    [report appendString:@"\n[Navigation/router runtime classes]\n"];
    for (NSString *line in CENavigationRouterClasses()) [report appendFormat:@"%@\n", line];

    [report appendString:@"\n[Database candidates]\n"];
    for (NSString *line in CEDatabaseCandidates()) [report appendFormat:@"%@\n", line];
    [report appendString:@"\n[Bundled images]\n"];
    for (NSString *line in CEBundledImages()) [report appendFormat:@"%@\n", line];
    [report appendString:@"\n[Interesting runtime classes]\n"];
    for (NSString *line in CEInterestingRuntimeClasses()) [report appendFormat:@"%@\n", line];
    [report appendString:@"\n[Target runtime details]\n"];
    for (NSString *line in CERuntimeDetails()) [report appendFormat:@"%@\n", line];

    return report;
}

void CECopyDiagnostics(UIView *sourceView, NSString *contextIdentifier) {
    NSString *report = CEDiagnosticsReport(sourceView, contextIdentifier);
    UIPasteboard.generalPasteboard.string = report;
    CEShowAlert(@"诊断信息已复制", @"请直接返回当前 ChatGPT 对话，把剪贴板内容粘贴发送给我。诊断内容不会包含 Authorization/Cookie 的值。");
}
