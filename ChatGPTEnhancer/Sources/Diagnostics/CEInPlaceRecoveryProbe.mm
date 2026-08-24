#import "CEInPlaceRecoveryProbe.h"
#import "CERecoveryDiagnostics.h"
#import "../Core/CECore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static NSString *CEInPlaceLastSnapshot = @"<not captured>";
static NSString *CEInPlaceBestFinalStreamSnapshot = nil;
static NSDate *CEInPlaceBestFinalStreamDate = nil;

typedef char *(*CESwiftDemangleFn)(const char *, size_t, char *, size_t *, uint32_t);

typedef struct {
    uintptr_t isaMask;
    Class targets[4];
    uintptr_t found[16];
    NSUInteger targetCount;
    NSUInteger foundCount;
} CEProbeHeapScanContext;

static uintptr_t CEProbeIsaMask(void) {
    static uintptr_t mask = 0; static dispatch_once_t once;
    dispatch_once(&once, ^{ uintptr_t *symbol = (uintptr_t *)dlsym(RTLD_DEFAULT, "objc_debug_isa_class_mask"); if (symbol) mask = *symbol; });
    return mask;
}

static NSSet<NSValue *> *CEProbeKnownClasses(void) {
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

static Class CEProbeHeapClass(uintptr_t bits, size_t *allocationOut) {
    if (!bits || (bits & 7) != 0) return Nil;
    void *ptr = (void *)bits; if (!malloc_zone_from_ptr(ptr)) return Nil;
    size_t allocation = malloc_size(ptr); if (allocation < sizeof(uintptr_t) || allocation > 1024 * 1024) return Nil;
    uintptr_t isa = 0; memcpy(&isa, ptr, sizeof(isa)); uintptr_t mask = CEProbeIsaMask(); uintptr_t classBits = mask ? (isa & mask) : isa;
    if (!classBits || ![CEProbeKnownClasses() containsObject:[NSValue valueWithPointer:(const void *)classBits]]) return Nil;
    if (allocationOut) *allocationOut = allocation;
    return (__bridge Class)(const void *)classBits;
}

static BOOL CEProbeRangeInBundleSegment(uintptr_t pointer, size_t length, vm_prot_t required, NSString **imageName, uintptr_t *imageOffset) {
    if (!pointer || !length) return NO;
    uintptr_t requestedEnd = pointer + length; if (requestedEnd < pointer) return NO;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @""; uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *rawPath = _dyld_get_image_name(i); const struct mach_header *header32 = _dyld_get_image_header(i); if (!rawPath || !header32 || header32->magic != MH_MAGIC_64) continue;
        NSString *path = [NSString stringWithUTF8String:rawPath]; if (bundlePath.length && ![path hasPrefix:bundlePath]) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)header32; intptr_t slide = _dyld_get_image_vmaddr_slide(i); const uint8_t *cursor = (const uint8_t *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cursor;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
                if ((segment->initprot & required) == required && segment->vmsize) {
                    uintptr_t start = (uintptr_t)(slide + (intptr_t)segment->vmaddr); uintptr_t end = start + (uintptr_t)segment->vmsize;
                    if (pointer >= start && requestedEnd <= end) { if (imageName) *imageName = path.lastPathComponent; if (imageOffset) *imageOffset = pointer - (uintptr_t)header; return YES; }
                }
            }
            if (!lc->cmdsize) break; cursor += lc->cmdsize;
        }
    }
    return NO;
}

static BOOL CEProbeReadable(uintptr_t address, size_t length) {
    if (!address || !length) return NO;
    void *heap = (void *)address; if (malloc_zone_from_ptr(heap)) { size_t allocation = malloc_size(heap); if (allocation >= length) return YES; }
    return CEProbeRangeInBundleSegment(address, length, VM_PROT_READ, NULL, NULL);
}

static NSString *CEProbeDemangleCString(const char *raw) {
    if (!raw || !raw[0]) return @"<nil>";
    const char *candidate = raw[0] == '_' ? raw + 1 : raw;
    CESwiftDemangleFn demangle = (CESwiftDemangleFn)dlsym(RTLD_DEFAULT, "swift_demangle");
    if (!demangle || candidate[0] != '$') return [NSString stringWithUTF8String:raw] ?: @"<invalid>";
    char *result = demangle(candidate, strlen(candidate), NULL, NULL, 0); if (!result) return [NSString stringWithUTF8String:raw] ?: @"<invalid>";
    NSString *value = [NSString stringWithUTF8String:result] ?: @"<invalid>"; free(result); return value;
}

static NSString *CEProbePointerDescription(uintptr_t pointer) {
    if (!pointer) return @"0x0";
    size_t allocation = 0; Class heapClass = CEProbeHeapClass(pointer, &allocation); if (heapClass) return [NSString stringWithFormat:@"0x%llx heap=%@ alloc=%zu", (unsigned long long)pointer, NSStringFromClass(heapClass), allocation];
    NSString *image = nil; uintptr_t offset = 0;
    if (CEProbeRangeInBundleSegment(pointer, 1, VM_PROT_EXECUTE, &image, &offset)) {
        Dl_info info = {0}; NSString *symbol = @"<stripped>"; if (dladdr((const void *)pointer, &info) && info.dli_sname) symbol = CEProbeDemangleCString(info.dli_sname);
        return [NSString stringWithFormat:@"0x%llx code=%@+0x%llx symbol=%@", (unsigned long long)pointer, image ?: @"<image>", (unsigned long long)offset, symbol];
    }
    if (CEProbeRangeInBundleSegment(pointer, 1, VM_PROT_READ, &image, &offset)) return [NSString stringWithFormat:@"0x%llx data=%@+0x%llx", (unsigned long long)pointer, image ?: @"<image>", (unsigned long long)offset];
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)pointer];
}

static NSString *CEProbeHexBytes(uintptr_t pointer, size_t length) {
    if (!pointer || !length || !CEProbeReadable(pointer, length)) return @"<unreadable>";
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2]; const uint8_t *bytes = (const uint8_t *)pointer;
    for (size_t i = 0; i < length; i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

static BOOL CEProbeContainsController(UIViewController *root, UIViewController *target) {
    if (!root || !target) return NO; if (root == target) return YES;
    for (UIViewController *child in root.childViewControllers) if (CEProbeContainsController(child, target)) return YES;
    return NO;
}

static void CEProbeCollectMessages(UIViewController *vc, NSMutableArray<UIViewController *> *out, NSUInteger depth) {
    if (!vc || depth > 18) return;
    if ([NSStringFromClass(vc.class) isEqualToString:@"ChatGPTMessages.MessagesViewController"]) [out addObject:vc];
    if (vc.presentedViewController) CEProbeCollectMessages(vc.presentedViewController, out, depth + 1);
    for (UIViewController *child in vc.childViewControllers) CEProbeCollectMessages(child, out, depth + 1);
}

static NSInteger CEProbeNavigationScore(UIViewController *messages) {
    NSInteger score = messages.viewIfLoaded.window ? 100 : 0; UIViewController *cursor = messages; UINavigationController *nav = nil; UIViewController *route = nil;
    while (cursor.parentViewController) {
        UIViewController *parent = cursor.parentViewController;
        if ([parent isKindOfClass:UINavigationController.class]) { nav = (UINavigationController *)parent; route = cursor; break; }
        cursor = parent;
    }
    if (!nav || !route) return score;
    NSUInteger index = [nav.viewControllers indexOfObjectIdenticalTo:route]; if (index != NSNotFound) score += (NSInteger)index * 10;
    if (nav.topViewController == route || CEProbeContainsController(nav.topViewController, messages)) score += 10000;
    return score;
}

static UIViewController *CEProbeActiveMessages(void) {
    UIWindow *window = CEKeyWindow(); if (!window.rootViewController) return nil;
    NSMutableArray<UIViewController *> *candidates = [NSMutableArray array]; CEProbeCollectMessages(window.rootViewController, candidates, 0);
    UIViewController *best = nil; NSInteger bestScore = NSIntegerMin;
    for (UIViewController *candidate in candidates) { NSInteger score = CEProbeNavigationScore(candidate); if (!best || score > bestScore) { best = candidate; bestScore = score; } }
    return best;
}

static BOOL CEProbeValidateObjectPointer(uintptr_t bits, NSString *expectedClassName, NSString **detail) {
    size_t allocation = 0; Class cls = CEProbeHeapClass(bits, &allocation); Class expected = NSClassFromString(expectedClassName);
    BOOL ok = cls && expected && (cls == expected || [NSStringFromClass(cls) isEqualToString:expectedClassName]);
    if (detail) *detail = [NSString stringWithFormat:@"ptr=0x%llx class=%@ alloc=%zu expected=%@ match=%@", (unsigned long long)bits, cls ? NSStringFromClass(cls) : @"<nil>", allocation, expectedClassName, ok ? @"YES" : @"NO"];
    return ok;
}

static uintptr_t CEProbeReadIvarWord(void *object, Class cls, const char *name, NSUInteger wordIndex) {
    if (!object || !cls || !name) return 0; Ivar ivar = class_getInstanceVariable(cls, name); if (!ivar) return 0;
    ptrdiff_t offset = ivar_getOffset(ivar) + (ptrdiff_t)(wordIndex * sizeof(uintptr_t)); if (offset < 0 || (size_t)offset + sizeof(uintptr_t) > class_getInstanceSize(cls)) return 0;
    uintptr_t word = 0; memcpy(&word, (const uint8_t *)object + offset, sizeof(word)); return word;
}

static void CEProbeAppendIvarWords(NSMutableArray<NSString *> *lines, uintptr_t object, Class cls, NSString *field, NSUInteger wordCount, NSString *label) {
    if (!object || !cls || !field.length) return; Ivar ivar = class_getInstanceVariable(cls, field.UTF8String); if (!ivar) { [lines addObject:[NSString stringWithFormat:@"%@ %@.%@=<missing>", label ?: @"STATE", NSStringFromClass(cls), field]]; return; }
    ptrdiff_t offset = ivar_getOffset(ivar); size_t instanceSize = class_getInstanceSize(cls); if (offset < 0 || (size_t)offset >= instanceSize) return;
    size_t available = instanceSize - (size_t)offset; NSUInteger count = MIN(wordCount, (NSUInteger)(available / sizeof(uintptr_t))); NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) { uintptr_t word = 0; memcpy(&word, (const uint8_t *)object + offset + i * sizeof(uintptr_t), sizeof(word)); [values addObject:[NSString stringWithFormat:@"w%lu=%@", (unsigned long)i, CEProbePointerDescription(word)]]; }
    size_t rawLength = MIN((size_t)32, available); [lines addObject:[NSString stringWithFormat:@"%@ %@.%@ offset=0x%tx %@ raw=%@", label ?: @"STATE", NSStringFromClass(cls), field, offset, values.count ? [values componentsJoinedByString:@" "] : @"<no words>", CEProbeHexBytes(object + (uintptr_t)offset, rawLength)]];
}

static void CEProbeAppendMethods(NSMutableArray<NSString *> *lines, Class cls, NSString *label) {
    if (!cls) { [lines addObject:[NSString stringWithFormat:@"%@ methods=<class nil>", label]]; return; }
    unsigned int count = 0; Method *methods = class_copyMethodList(cls, &count); [lines addObject:[NSString stringWithFormat:@"%@ class=%@ instanceMethods=%u", label, NSStringFromClass(cls), count]];
    for (unsigned int i = 0; i < count && i < 40; i++) [lines addObject:[NSString stringWithFormat:@"  - %@ | %s", NSStringFromSelector(method_getName(methods[i])), method_getTypeEncoding(methods[i]) ?: ""]];
    free(methods);
}

static void CEProbeAppendExecutableTable(NSMutableArray<NSString *> *lines, uintptr_t table, NSString *label, NSUInteger maxEntries) {
    if (!table || !CEProbeReadable(table, maxEntries * sizeof(uintptr_t))) { [lines addObject:[NSString stringWithFormat:@"%@ table=%@ readable=NO", label, CEProbePointerDescription(table)]]; return; }
    [lines addObject:[NSString stringWithFormat:@"%@ table=%@", label, CEProbePointerDescription(table)]];
    NSUInteger hits = 0;
    for (NSUInteger i = 0; i < maxEntries && hits < 32; i++) {
        uintptr_t value = 0; memcpy(&value, (const void *)(table + i * sizeof(uintptr_t)), sizeof(value));
        if (!CEProbeRangeInBundleSegment(value, 1, VM_PROT_EXECUTE, NULL, NULL)) continue;
        [lines addObject:[NSString stringWithFormat:@"  [%02lu] %@", (unsigned long)i, CEProbePointerDescription(value)]]; hits++;
    }
    if (!hits) [lines addObject:@"  <no executable entries in scanned range>"];
}

static BOOL CEProbeInterestingSymbol(NSString *value) {
    NSString *lower = value.lowercaseString;
    NSArray<NSString *> *needles = @[@"defaultconversationcoordinator", @"defaultconversationrepository", @"conversationfinalstream", @"resumeconversation", @"recoverconversation", @"fetchconversation", @"updateconversation", @"refreshconversation", @"conversationrepository", @"conversationdetail", @"repositoryupdate", @"openconversation", @"messageupdateplanningqueue"];
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static NSArray<NSString *> *CEProbeInterestingSymbols(void) {
    static NSArray<NSString *> *cached = nil; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *out = [NSMutableArray array]; NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @""; uint32_t imageCount = _dyld_image_count();
        for (uint32_t i = 0; i < imageCount && out.count < 100; i++) {
            const char *rawPath = _dyld_get_image_name(i); const struct mach_header *header32 = _dyld_get_image_header(i); if (!rawPath || !header32 || header32->magic != MH_MAGIC_64) continue;
            NSString *path = [NSString stringWithUTF8String:rawPath]; if (bundlePath.length && ![path hasPrefix:bundlePath]) continue; if ([path.lastPathComponent containsString:@"ChatGPTEnhancer"]) continue;
            const struct mach_header_64 *header = (const struct mach_header_64 *)header32; intptr_t slide = _dyld_get_image_vmaddr_slide(i); const struct symtab_command *symtab = NULL; const struct segment_command_64 *linkedit = NULL; const uint8_t *cursor = (const uint8_t *)(header + 1);
            for (uint32_t c = 0; c < header->ncmds; c++) {
                const struct load_command *lc = (const struct load_command *)cursor;
                if (lc->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)cursor;
                else if (lc->cmd == LC_SEGMENT_64) { const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor; if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) linkedit = segment; }
                if (!lc->cmdsize) break; cursor += lc->cmdsize;
            }
            if (!symtab || !linkedit || !symtab->nsyms || !symtab->strsize) continue;
            uintptr_t linkeditBase = (uintptr_t)(slide + (intptr_t)linkedit->vmaddr - (intptr_t)linkedit->fileoff); uintptr_t symbolsAddress = linkeditBase + symtab->symoff; uintptr_t stringsAddress = linkeditBase + symtab->stroff;
            if (!CEProbeReadable(symbolsAddress, (size_t)symtab->nsyms * sizeof(struct nlist_64)) || !CEProbeReadable(stringsAddress, symtab->strsize)) continue;
            const struct nlist_64 *symbols = (const struct nlist_64 *)symbolsAddress; const char *strings = (const char *)stringsAddress;
            for (uint32_t s = 0; s < symtab->nsyms && out.count < 100; s++) {
                uint32_t stringIndex = symbols[s].n_un.n_strx; if (!stringIndex || stringIndex >= symtab->strsize) continue; const char *rawName = strings + stringIndex; size_t remaining = symtab->strsize - stringIndex; size_t rawLength = strnlen(rawName, remaining); if (!rawLength || rawLength == remaining) continue;
                NSString *raw = [[NSString alloc] initWithBytes:rawName length:rawLength encoding:NSUTF8StringEncoding]; if (!raw.length || !CEProbeInterestingSymbol(raw)) continue;
                NSString *demangled = CEProbeDemangleCString(raw.UTF8String); [out addObject:[NSString stringWithFormat:@"%@ | raw=%@ | value=0x%llx", demangled, raw, (unsigned long long)symbols[s].n_value]];
            }
        }
        cached = [out copy];
    });
    return cached ?: @[];
}

static BOOL CEProbeGraphInterestingClass(NSString *name) {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *needles = @[@"conversation", @"repository", @"coordinator", @"stream", @"message", @"requeststate", @"reference", @"subject", @"task"];
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static BOOL CEProbeGraphEmitClass(NSString *name) {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *needles = @[@"conversationfinalstream", @"repository", @"coordinator", @"stream", @"requeststate", @"task"];
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static void CEProbeAppendClosureDetails(NSMutableArray<NSString *> *lines, uintptr_t function, uintptr_t context, NSString *label) {
    NSString *image = nil; uintptr_t offset = 0; BOOL executable = CEProbeRangeInBundleSegment(function, 1, VM_PROT_EXECUTE, &image, &offset);
    [lines addObject:[NSString stringWithFormat:@"%@ function=%@ context=%@", label, CEProbePointerDescription(function), CEProbePointerDescription(context)]];
    if (executable) [lines addObject:[NSString stringWithFormat:@"%@ codeBytes=%@", label, CEProbeHexBytes(function, 96)]];
    if (context && malloc_zone_from_ptr((void *)context)) {
        size_t allocation = malloc_size((void *)context); size_t bytes = MIN((size_t)96, allocation); [lines addObject:[NSString stringWithFormat:@"%@ contextAlloc=%zu contextBytes=%@", label, allocation, CEProbeHexBytes(context, bytes)]];
        NSMutableArray<NSString *> *pointers = [NSMutableArray array]; size_t scan = MIN((size_t)128, allocation);
        for (size_t i = 0; i + sizeof(uintptr_t) <= scan && pointers.count < 16; i += sizeof(uintptr_t)) { uintptr_t word = 0; memcpy(&word, (const uint8_t *)context + i, sizeof(word)); Class cls = CEProbeHeapClass(word, NULL); if (cls) [pointers addObject:[NSString stringWithFormat:@"+0x%zx=%@", i, CEProbePointerDescription(word)]]; }
        if (pointers.count) [lines addObject:[NSString stringWithFormat:@"%@ contextObjects=%@", label, [pointers componentsJoinedByString:@" | "]]];
    }
}

static void CEProbeAppendFinalStreamState(NSMutableArray<NSString *> *lines, uintptr_t object, Class cls) {
    NSString *name = NSStringFromClass(cls); [lines addObject:[NSString stringWithFormat:@"FINAL-STREAM-INSTANCE %@ %@", name, CEProbePointerDescription(object)]];
    for (NSString *field in @[@"resumeConversationStream", @"initialStream"]) {
        Ivar ivar = class_getInstanceVariable(cls, field.UTF8String); if (!ivar) continue; ptrdiff_t offset = ivar_getOffset(ivar); if (offset < 0 || (size_t)offset + sizeof(uintptr_t) * 2 > class_getInstanceSize(cls)) continue;
        uintptr_t words[2] = {0, 0}; memcpy(words, (const uint8_t *)object + offset, sizeof(words)); CEProbeAppendClosureDetails(lines, words[0], words[1], [NSString stringWithFormat:@"FINAL-STREAM %@.%@ offset=0x%tx", name, field, offset]);
    }
    for (NSString *field in @[@"resumeConversationToken", @"resumeRetries", @"hasAttemptedRecoverWithFetch", @"hasAttemptedRecoverWithNewPolling", @"hasRecoveredConversation", @"receivedMessageStreamComplete", @"recoveryEventSource", @"state"]) CEProbeAppendIvarWords(lines, object, cls, field, 4, @"FINAL-STREAM-STATE");
}

static void CEProbeAppendReachableGraph(NSMutableArray<NSString *> *lines, uintptr_t root) {
    if (!root) return; NSMutableArray<NSDictionary *> *queue = [NSMutableArray arrayWithObject:@{@"ptr": @(root), @"depth": @0}]; NSMutableSet<NSNumber *> *seen = [NSMutableSet set]; NSUInteger emitted = 0;
    while (queue.count && seen.count < 260 && emitted < 96) {
        NSDictionary *entry = queue.firstObject; [queue removeObjectAtIndex:0]; uintptr_t pointer = [entry[@"ptr"] unsignedLongLongValue]; NSUInteger depth = [entry[@"depth"] unsignedIntegerValue]; NSNumber *key = @(pointer); if ([seen containsObject:key]) continue; [seen addObject:key];
        size_t allocation = 0; Class cls = CEProbeHeapClass(pointer, &allocation); if (!cls) continue; NSString *name = NSStringFromClass(cls); if (!CEProbeGraphInterestingClass(name)) continue;
        BOOL emit = depth == 0 || CEProbeGraphEmitClass(name); if (emit) { [lines addObject:[NSString stringWithFormat:@"GRAPH depth=%lu %@", (unsigned long)depth, CEProbePointerDescription(pointer)]]; emitted++; }
        if ([name containsString:@"ConversationFinalStream"]) CEProbeAppendFinalStreamState(lines, pointer, cls);
        if (depth >= 4) continue; size_t scan = MIN(MIN(allocation, class_getInstanceSize(cls)), (size_t)8192);
        for (size_t offset = 0; offset + sizeof(uintptr_t) <= scan && queue.count < 320; offset += sizeof(uintptr_t)) {
            uintptr_t child = 0; memcpy(&child, (const uint8_t *)pointer + offset, sizeof(child)); Class childClass = CEProbeHeapClass(child, NULL); if (!childClass) continue; NSString *childName = NSStringFromClass(childClass); if (!CEProbeGraphInterestingClass(childName) || [seen containsObject:@(child)]) continue;
            NSDictionary *next = @{@"ptr": @(child), @"depth": @(depth + 1)}; if ([childName containsString:@"ConversationFinalStream"]) [queue insertObject:next atIndex:0]; else [queue addObject:next];
        }
    }
}

static kern_return_t CEProbeMemoryReader(task_t task, vm_address_t remoteAddress, vm_size_t size, void **localMemory) {
    if (task != mach_task_self() || !remoteAddress || !size || !localMemory) return KERN_INVALID_ARGUMENT; *localMemory = (void *)remoteAddress; return KERN_SUCCESS;
}

static void CEProbeRangeRecorder(task_t task, void *contextPointer, unsigned type, vm_range_t *ranges, unsigned count) {
    if (task != mach_task_self() || !contextPointer || !ranges || type != MALLOC_PTR_IN_USE_RANGE_TYPE) return; CEProbeHeapScanContext *context = (CEProbeHeapScanContext *)contextPointer;
    for (unsigned i = 0; i < count && context->foundCount < 16; i++) {
        uintptr_t pointer = (uintptr_t)ranges[i].address; if (!pointer || (pointer & 7) != 0 || ranges[i].size < sizeof(uintptr_t)) continue; uintptr_t isa = 0; memcpy(&isa, (const void *)pointer, sizeof(isa)); uintptr_t classBits = context->isaMask ? (isa & context->isaMask) : isa;
        for (NSUInteger t = 0; t < context->targetCount; t++) if (classBits == (uintptr_t)context->targets[t]) { context->found[context->foundCount++] = pointer; break; }
    }
}

static NSArray<NSNumber *> *CEProbeFindFinalStreamInstances(NSMutableArray<NSString *> *lines) {
    CEProbeHeapScanContext context = {0}; context.isaMask = CEProbeIsaMask(); NSArray<NSString *> *names = @[@"_TtCV13ConversationsP33_E5D2BCA009FFCA5C9A0611AC936C0D3523ConversationFinalStream5State", @"_TtCV13ConversationsP33_E5D2BCA009FFCA5C9A0611AC936C0D3523ConversationFinalStream7Storage", @"_TtCV13ConversationsP33_E5D2BCA009FFCA5C9A0611AC936C0D3523ConversationFinalStream19RecoveryEventSource"];
    for (NSString *name in names) { Class cls = NSClassFromString(name); if (cls && context.targetCount < 4) context.targets[context.targetCount++] = cls; }
    if (!context.targetCount) { [lines addObject:@"HEAP-FINAL-STREAM targetClasses=<none loaded>"]; return @[]; }
    vm_address_t *zones = NULL; unsigned zoneCount = 0; kern_return_t kr = malloc_get_all_zones(mach_task_self(), CEProbeMemoryReader, &zones, &zoneCount); if (kr != KERN_SUCCESS || !zones) { [lines addObject:[NSString stringWithFormat:@"HEAP-FINAL-STREAM malloc_get_all_zones kr=%d", kr]]; return @[]; }
    for (unsigned i = 0; i < zoneCount && context.foundCount < 16; i++) {
        malloc_zone_t *zone = (malloc_zone_t *)zones[i]; if (!zone || !zone->introspect || !zone->introspect->enumerator) continue;
        zone->introspect->enumerator(mach_task_self(), &context, MALLOC_PTR_IN_USE_RANGE_TYPE, (vm_address_t)zone, CEProbeMemoryReader, CEProbeRangeRecorder);
    }
    NSMutableArray<NSNumber *> *result = [NSMutableArray array]; for (NSUInteger i = 0; i < context.foundCount; i++) [result addObject:@(context.found[i])];
    [lines addObject:[NSString stringWithFormat:@"HEAP-FINAL-STREAM zones=%u targets=%lu found=%lu", zoneCount, (unsigned long)context.targetCount, (unsigned long)result.count]]; return result;
}

static NSArray<NSString *> *CEProbeCapture(NSString *reason) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array]; UIViewController *messages = CEProbeActiveMessages();
    [lines addObject:[NSString stringWithFormat:@"reason=%@ context=%@ appState=%ld messages=%@ ptr=%p score=%ld", reason ?: @"<nil>", [CEConversationContext shared].conversationID ?: @"<nil>", (long)UIApplication.sharedApplication.applicationState, messages ? NSStringFromClass(messages.class) : @"<nil>", messages, messages ? (long)CEProbeNavigationScore(messages) : -1L]];
    if (!messages) return lines;
    Ivar vmIvar = class_getInstanceVariable(messages.class, "viewModel"); if (!vmIvar) { [lines addObject:@"viewModel ivar=<missing>"]; return lines; }
    uintptr_t vm = 0; memcpy(&vm, (const uint8_t *)(__bridge const void *)messages + ivar_getOffset(vmIvar), sizeof(vm)); NSString *vmDetail = nil; BOOL vmOK = CEProbeValidateObjectPointer(vm, @"ChatGPTMessages.MessagesViewModel", &vmDetail); [lines addObject:[@"viewModel " stringByAppendingString:vmDetail ?: @"<nil>"]]; if (!vmOK) return lines;
    Class vmClass = NSClassFromString(@"ChatGPTMessages.MessagesViewModel"); CEProbeAppendIvarWords(lines, vm, vmClass, @"_conversationState", 4, @"MESSAGES-VM-STATE"); CEProbeAppendIvarWords(lines, vm, vmClass, @"_coordinatorIsStreaming", 2, @"MESSAGES-VM-STATE");
    uintptr_t coordinator = CEProbeReadIvarWord((void *)vm, vmClass, "conversationCoordinator", 0); uintptr_t coordinatorWitness = CEProbeReadIvarWord((void *)vm, vmClass, "conversationCoordinator", 1); NSString *coordDetail = nil; BOOL coordOK = CEProbeValidateObjectPointer(coordinator, @"Conversations.DefaultConversationCoordinator", &coordDetail); [lines addObject:[@"coordinator " stringByAppendingString:coordDetail ?: @"<nil>"]]; [lines addObject:[NSString stringWithFormat:@"coordinatorWitness=%@", CEProbePointerDescription(coordinatorWitness)]]; CEProbeAppendExecutableTable(lines, coordinatorWitness, @"COORD-WITNESS", 96); if (!coordOK) return lines;
    Class coordinatorClass = NSClassFromString(@"Conversations.DefaultConversationCoordinator"); CEProbeAppendMethods(lines, coordinatorClass, @"COORD-METHODS");
    for (NSString *field in @[@"_state", @"_serverStreamingStatus", @"_remoteConversationId", @"conversation", @"streamTask", @"streamTaskCancellationReason", @"eventSourceMessageStreamEnabled", @"shouldPreserveTerminalErrorAfterRepositoryUpdate"]) CEProbeAppendIvarWords(lines, coordinator, coordinatorClass, field, 5, @"COORD-STATE");
    Ivar repositoryIvar = class_getInstanceVariable(coordinatorClass, "conversationRepository"); uintptr_t repository = 0;
    if (repositoryIvar) {
        ptrdiff_t offset = ivar_getOffset(repositoryIvar); [lines addObject:[NSString stringWithFormat:@"conversationRepository offset=0x%tx", offset]];
        for (NSUInteger i = 0; i < 5; i++) { uintptr_t word = 0; memcpy(&word, (const uint8_t *)coordinator + offset + i * sizeof(uintptr_t), sizeof(word)); [lines addObject:[NSString stringWithFormat:@"  repoWord[%lu]=%@", (unsigned long)i, CEProbePointerDescription(word)]]; if (i == 0) repository = word; else if (CEProbeRangeInBundleSegment(word, 64 * sizeof(uintptr_t), VM_PROT_READ, NULL, NULL) && !CEProbeRangeInBundleSegment(word, 1, VM_PROT_EXECUTE, NULL, NULL)) CEProbeAppendExecutableTable(lines, word, [NSString stringWithFormat:@"REPO-TABLE-%lu", (unsigned long)i], 64); }
    } else [lines addObject:@"conversationRepository ivar=<missing>"];
    Class repositoryClass = CEProbeHeapClass(repository, NULL); if (repositoryClass) CEProbeAppendMethods(lines, repositoryClass, @"REPO-METHODS");
    [lines addObject:@"-- reachable live graph --"]; CEProbeAppendReachableGraph(lines, coordinator);
    [lines addObject:@"-- exact live ConversationFinalStream heap instances --"]; for (NSNumber *value in CEProbeFindFinalStreamInstances(lines)) { uintptr_t pointer = value.unsignedLongLongValue; Class cls = CEProbeHeapClass(pointer, NULL); if (cls) CEProbeAppendFinalStreamState(lines, pointer, cls); }
    [lines addObject:@"-- matching Mach-O symbols --"]; NSArray<NSString *> *symbols = CEProbeInterestingSymbols(); if (symbols.count) [lines addObjectsFromArray:symbols]; else [lines addObject:@"<no matching symbols in LC_SYMTAB>"];
    return lines;
}

void CEInPlaceRecoveryProbe(NSString *reason) {
    void (^work)(void) = ^{
        CERecoveryDiagnosticMark(@"IN-PLACE RECOVERY PROBE"); NSArray<NSString *> *lines = CEProbeCapture(reason ?: @"manual"); NSString *snapshot = [lines componentsJoinedByString:@"\n"]; CEInPlaceLastSnapshot = snapshot;
        BOOL hasFinalStream = [snapshot containsString:@"FINAL-STREAM-INSTANCE"] || [snapshot containsString:@"FINAL-STREAM "]; if (hasFinalStream) { CEInPlaceBestFinalStreamSnapshot = snapshot; CEInPlaceBestFinalStreamDate = NSDate.date; }
        for (NSString *line in lines) CERecoveryDiagnosticLog(@"INPLACE30", @"%@", line);
    };
    if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
}

NSString *CEInPlaceRecoveryProbeSnapshot(void) {
    if (!CEInPlaceBestFinalStreamSnapshot.length) return CEInPlaceLastSnapshot ?: @"<not captured>";
    if ([CEInPlaceBestFinalStreamSnapshot isEqualToString:CEInPlaceLastSnapshot]) return [NSString stringWithFormat:@"[best live final-stream snapshot at %@]\n%@", CEInPlaceBestFinalStreamDate ?: (id)@"<nil>", CEInPlaceBestFinalStreamSnapshot];
    return [NSString stringWithFormat:@"[best live final-stream snapshot at %@]\n%@\n\n[latest snapshot]\n%@", CEInPlaceBestFinalStreamDate ?: (id)@"<nil>", CEInPlaceBestFinalStreamSnapshot, CEInPlaceLastSnapshot ?: @"<nil>"];
}