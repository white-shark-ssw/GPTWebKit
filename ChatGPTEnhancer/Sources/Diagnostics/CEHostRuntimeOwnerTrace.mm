#import "CEHostRuntimeOwnerTrace.h"
#import "CEConversationIdentityTrace.h"
#import "../Core/CECore.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

static NSObject *CEHostRuntimeOwnerTraceLock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static NSString *CEHostRuntimeBounded(NSString *value, NSUInteger maxLength) {
    if (!value.length) return @"<none>";
    return value.length <= maxLength ? value : [[value substringToIndex:maxLength] stringByAppendingString:@"…"];
}

static BOOL CEHostRuntimeContainsAny(NSString *value, NSArray<NSString *> *tokens) {
    NSString *lower = value.lowercaseString ?: @"";
    for (NSString *token in tokens) if ([lower containsString:token]) return YES;
    return NO;
}

static NSString *CEHostRuntimeCanonicalPath(const char *path) {
    if (!path || !path[0]) return nil;
    char resolved[PATH_MAX];
    if (realpath(path, resolved)) return [NSString stringWithUTF8String:resolved];
    return [[[NSString alloc] initWithUTF8String:path] stringByStandardizingPath];
}

static BOOL CEHostRuntimePathInsideBundle(NSString *path, NSString *bundlePath) {
    if (!path.length || !bundlePath.length) return NO;
    if ([path isEqualToString:bundlePath]) return YES;
    return [path hasPrefix:[bundlePath stringByAppendingString:@"/"]];
}

static void CEHostRuntimeInsertNearest(NSMutableArray<NSDictionary *> *candidates, NSDictionary *candidate) {
    [candidates addObject:candidate];
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long da = llabs([a[@"delta"] longLongValue]); long long db = llabs([b[@"delta"] longLongValue]);
        if (da < db) return NSOrderedAscending; if (da > db) return NSOrderedDescending; return NSOrderedSame;
    }];
    if (candidates.count > 6) [candidates removeLastObject];
}

static BOOL CEHostRuntimeMethodInfo(Class cls, Method method, NSString *kind, uintptr_t mainBase, NSArray<NSDictionary *> *references, NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *nearest) {
    if (!method) return NO;
    IMP imp = method_getImplementation(method); if (!imp) return NO;
    Dl_info info = {}; if (!dladdr((const void *)imp, &info) || (uintptr_t)info.dli_fbase != mainBase) return NO;
    unsigned long long offset = (unsigned long long)((uintptr_t)imp - mainBase);
    NSString *className = CEHostRuntimeBounded(NSStringFromClass(cls), 220); NSString *selector = CEHostRuntimeBounded(NSStringFromSelector(method_getName(method)), 220);
    for (NSDictionary *reference in references) {
        unsigned long long target = [reference[@"offset"] unsignedLongLongValue]; long long delta = (long long)target - (long long)offset;
        NSMutableArray<NSDictionary *> *bucket = nearest[reference[@"label"]]; if (!bucket) { bucket = [NSMutableArray array]; nearest[reference[@"label"]] = bucket; }
        CEHostRuntimeInsertNearest(bucket, @{ @"offset": @(offset), @"delta": @(delta), @"class": className, @"selector": selector, @"kind": kind ?: @"instance" });
    }
    return YES;
}

static NSArray<NSString *> *CEHostRuntimeSemanticSelectors(Class cls) {
    static NSArray<NSString *> *tokens; static dispatch_once_t once;
    dispatch_once(&once, ^{ tokens = @[@"conversation", @"chat", @"thread", @"message", @"history", @"route", @"sidebar", @"navigation", @"refresh", @"reload", @"hydrate"]; });
    NSMutableOrderedSet<NSString *> *selectors = [NSMutableOrderedSet orderedSet];
    for (int pass = 0; pass < 2; pass++) {
        Class methodClass = pass == 0 ? cls : object_getClass(cls); unsigned int count = 0; Method *methods = class_copyMethodList(methodClass, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *selector = NSStringFromSelector(method_getName(methods[i])); if (!CEHostRuntimeContainsAny(selector, tokens)) continue;
            [selectors addObject:[NSString stringWithFormat:@"%@%@", pass == 0 ? @"-" : @"+", CEHostRuntimeBounded(selector, 180)]]; if (selectors.count >= 24) break;
        }
        free(methods); if (selectors.count >= 24) break;
    }
    return selectors.array;
}

static void CEHostRuntimeLogDirectReference(NSString *conversationID, NSDictionary *reference, uintptr_t mainBase) {
    unsigned long long targetOffset = [reference[@"offset"] unsignedLongLongValue]; const void *address = (const void *)(mainBase + (uintptr_t)targetOffset); Dl_info info = {};
    BOOL resolved = dladdr(address, &info) != 0; BOOL sameImage = resolved && (uintptr_t)info.dli_fbase == mainBase;
    NSString *image = resolved && info.dli_fname ? [[[NSString alloc] initWithUTF8String:info.dli_fname] lastPathComponent] : @"<none>";
    NSString *symbol = resolved && info.dli_sname ? CEHostRuntimeBounded([[NSString alloc] initWithUTF8String:info.dli_sname], 260) : @"<none>";
    unsigned long long symbolOffset = sameImage && info.dli_saddr ? (unsigned long long)((uintptr_t)info.dli_saddr - mainBase) : 0ULL;
    long long symbolDelta = symbolOffset ? (long long)targetOffset - (long long)symbolOffset : LLONG_MIN;
    CEConversationIdentityTraceLog(@"RUNTIME-OWNER-DLADDR", @"target=%@ label=%@ referenceOffset=%@ resolved=%@ sameMainImage=%@ image=%@ symbol=%@ symbolOffset=%@ symbolDelta=%@",
        conversationID ?: @"<none>", reference[@"label"], reference[@"offset"], resolved ? @"YES" : @"NO", sameImage ? @"YES" : @"NO", image ?: @"<none>", symbol,
        symbolOffset ? [NSString stringWithFormat:@"%llu", symbolOffset] : @"<none>", symbolOffset ? [NSString stringWithFormat:@"%lld", symbolDelta] : @"<none>");
}

static void CEHostRuntimeLogMap(NSString *conversationID) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    NSString *currentApp = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown"; NSString *referenceApp = @"1.2026.202";
    const char *mainImageName = _dyld_image_count() ? _dyld_get_image_name(0) : NULL; const struct mach_header *header = _dyld_image_count() ? _dyld_get_image_header(0) : NULL;
    if (!mainImageName || !header) { CEConversationIdentityTraceLog(@"RUNTIME-OWNER", @"target=%@ result=no-main-image", conversationID ?: @"<none>"); return; }
    NSString *mainImageRaw = [[NSString alloc] initWithUTF8String:mainImageName] ?: @"<none>"; NSString *mainImage = CEHostRuntimeCanonicalPath(mainImageName) ?: mainImageRaw; uintptr_t mainBase = (uintptr_t)header;
    NSString *bundlePath = CEHostRuntimeCanonicalPath(NSBundle.mainBundle.bundlePath.fileSystemRepresentation) ?: NSBundle.mainBundle.bundlePath;
    BOOL comparable = [currentApp isEqualToString:referenceApp];
    NSArray<NSDictionary *> *references = comparable ? @[
        @{ @"label": @"network-76920605", @"offset": @76920605ULL },
        @{ @"label": @"network-48186293", @"offset": @48186293ULL },
        @{ @"label": @"network-76937441", @"offset": @76937441ULL },
        @{ @"label": @"nav-82300348", @"offset": @82300348ULL },
        @{ @"label": @"nav-82123672", @"offset": @82123672ULL },
        @{ @"label": @"nav-1884732", @"offset": @1884732ULL },
        @{ @"label": @"nav-12860372", @"offset": @12860372ULL }
    ] : @[];
    if (comparable) for (NSDictionary *reference in references) CEHostRuntimeLogDirectReference(conversationID, reference, mainBase);

    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *nearest = [NSMutableDictionary dictionary];
    static NSArray<NSString *> *classTokens; static dispatch_once_t tokenOnce;
    dispatch_once(&tokenOnce, ^{ classTokens = @[@"conversation", @"chat", @"thread", @"message", @"history", @"route", @"sidebar", @"navigation"]; });
    int classCount = objc_getClassList(NULL, 0); Class *classes = classCount > 0 ? (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class)) : NULL;
    if (!classes) { CEConversationIdentityTraceLog(@"RUNTIME-OWNER", @"target=%@ result=no-class-buffer", conversationID ?: @"<none>"); return; }
    classCount = objc_getClassList(classes, classCount);
    NSUInteger appBundleClassCount = 0; NSUInteger mainPathClassCount = 0; NSUInteger mainIMPClassCount = 0; NSUInteger mainIMPMethodCount = 0; NSUInteger semanticClassCount = 0;
    for (int i = 0; i < classCount; i++) {
        Class cls = classes[i]; const char *rawClassImage = class_getImageName(cls); NSString *classImage = CEHostRuntimeCanonicalPath(rawClassImage); BOOL inAppBundle = CEHostRuntimePathInsideBundle(classImage, bundlePath); BOOL mainPathMatch = classImage.length && [classImage isEqualToString:mainImage];
        if (inAppBundle) appBundleClassCount++; if (mainPathMatch) mainPathClassCount++;
        NSString *className = NSStringFromClass(cls) ?: @"<unknown>"; NSArray<NSString *> *semanticSelectors = inAppBundle ? CEHostRuntimeSemanticSelectors(cls) : @[];
        if (inAppBundle && semanticClassCount < 100 && (CEHostRuntimeContainsAny(className, classTokens) || semanticSelectors.count)) {
            NSString *superName = class_getSuperclass(cls) ? NSStringFromClass(class_getSuperclass(cls)) : @"<none>"; NSString *imageName = classImage.lastPathComponent ?: (rawClassImage ? [[[NSString alloc] initWithUTF8String:rawClassImage] lastPathComponent] : @"<none>");
            CEConversationIdentityTraceLog(@"RUNTIME-OWNER-CLASS", @"target=%@ image=%@ mainPath=%@ class=%@ super=%@ selectors=%@", conversationID ?: @"<none>", imageName ?: @"<none>", mainPathMatch ? @"YES" : @"NO", CEHostRuntimeBounded(className, 220), CEHostRuntimeBounded(superName, 220), semanticSelectors.count ? [semanticSelectors componentsJoinedByString:@","] : @"<none>"); semanticClassCount++;
        }
        if (!inAppBundle && !mainPathMatch) continue;
        BOOL classHasMainIMP = NO;
        for (int pass = 0; pass < 2; pass++) {
            Class methodClass = pass == 0 ? cls : object_getClass(cls); unsigned int methodCount = 0; Method *methods = class_copyMethodList(methodClass, &methodCount);
            for (unsigned int j = 0; j < methodCount; j++) if (CEHostRuntimeMethodInfo(cls, methods[j], pass == 0 ? @"instance" : @"class", mainBase, comparable ? references : @[], nearest)) { mainIMPMethodCount++; classHasMainIMP = YES; }
            free(methods);
        }
        if (classHasMainIMP) mainIMPClassCount++;
    }
    free(classes);
    CEConversationIdentityTraceLog(@"RUNTIME-OWNER", @"target=%@ referenceApp=%@ currentApp=%@ comparable=%@ mainImage=%@ appBundleClasses=%lu mainPathClasses=%lu mainIMPClasses=%lu mainIMPMethods=%lu semanticClasses=%lu",
        conversationID ?: @"<none>", referenceApp, currentApp, comparable ? @"YES" : @"NO", mainImage.lastPathComponent ?: @"<none>", (unsigned long)appBundleClassCount, (unsigned long)mainPathClassCount, (unsigned long)mainIMPClassCount, (unsigned long)mainIMPMethodCount, (unsigned long)semanticClassCount);
    if (!comparable) return;
    for (NSDictionary *reference in references) {
        NSArray<NSDictionary *> *bucket = nearest[reference[@"label"]] ?: @[]; NSUInteger rank = 0;
        if (!bucket.count) CEConversationIdentityTraceLog(@"RUNTIME-OWNER-REF", @"target=%@ label=%@ referenceOffset=%@ result=no-main-objc-method", conversationID ?: @"<none>", reference[@"label"], reference[@"offset"]);
        for (NSDictionary *candidate in bucket) {
            long long delta = [candidate[@"delta"] longLongValue]; BOOL near = llabs(delta) <= 65536;
            CEConversationIdentityTraceLog(@"RUNTIME-OWNER-REF", @"target=%@ label=%@ referenceOffset=%@ rank=%lu kind=%@ class=%@ selector=%@ methodOffset=%@ delta=%lld near64k=%@", conversationID ?: @"<none>", reference[@"label"], reference[@"offset"], (unsigned long)++rank, candidate[@"kind"], candidate[@"class"], candidate[@"selector"], candidate[@"offset"], delta, near ? @"YES" : @"NO");
        }
    }
}

void CEHostRuntimeOwnerTraceStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:CEConversationContextDidChangeNotification object:[CEConversationContext shared] queue:nil usingBlock:^(__unused NSNotification *note) {
            if (!CEConversationIdentityTraceIsRecording()) return;
            NSString *conversationID = [CEConversationContext shared].conversationID; if (!conversationID.length) return;
            static NSString *lastConversationID = nil;
            @synchronized (CEHostRuntimeOwnerTraceLock()) { if ([lastConversationID isEqualToString:conversationID]) return; lastConversationID = [conversationID copy]; }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ CEHostRuntimeLogMap(conversationID); });
        }];
    });
}
