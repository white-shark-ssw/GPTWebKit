#import "CEInPlaceRecoveryProbe.h"
#import "CERecoveryDiagnostics.h"
#import "../Core/CECore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static NSString *CEInPlaceLastSnapshot = @"<not captured>";

typedef char *(*CESwiftDemangleFn)(const char *, size_t, char *, size_t *, uint32_t);

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

static BOOL CEProbeReadable(uintptr_t address, size_t length) {
    if (!address || !length) return NO;
    mach_vm_address_t region = (mach_vm_address_t)address; mach_vm_size_t size = 0; vm_region_basic_info_data_64_t info = {0}; mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64; mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = mach_vm_region(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (kr != KERN_SUCCESS || !(info.protection & VM_PROT_READ) || region > address) return NO;
    uintptr_t end = address + length; if (end < address) return NO;
    return end <= (uintptr_t)(region + size);
}

static BOOL CEProbePointerInBundleSegment(uintptr_t pointer, vm_prot_t required, NSString **imageName, uintptr_t *imageOffset) {
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *rawPath = _dyld_get_image_name(i); const struct mach_header *header32 = _dyld_get_image_header(i); if (!rawPath || !header32) continue;
        NSString *path = [NSString stringWithUTF8String:rawPath]; if (bundlePath.length && ![path hasPrefix:bundlePath]) continue;
        if (header32->magic != MH_MAGIC_64) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)header32; intptr_t slide = _dyld_get_image_vmaddr_slide(i); const uint8_t *cursor = (const uint8_t *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cursor;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
                if ((segment->initprot & required) == required && segment->vmsize) {
                    uintptr_t start = (uintptr_t)(slide + (intptr_t)segment->vmaddr); uintptr_t end = start + (uintptr_t)segment->vmsize;
                    if (pointer >= start && pointer < end) { if (imageName) *imageName = path.lastPathComponent; if (imageOffset) *imageOffset = pointer - (uintptr_t)header; return YES; }
                }
            }
            if (!lc->cmdsize) break; cursor += lc->cmdsize;
        }
    }
    return NO;
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
    NSString *image = nil; uintptr_t offset = 0; BOOL executable = CEProbePointerInBundleSegment(pointer, VM_PROT_EXECUTE, &image, &offset);
    if (executable) {
        Dl_info info = {0}; NSString *symbol = @"<stripped>";
        if (dladdr((const void *)pointer, &info) && info.dli_sname) symbol = CEProbeDemangleCString(info.dli_sname);
        return [NSString stringWithFormat:@"0x%llx code=%@+0x%llx symbol=%@", (unsigned long long)pointer, image ?: @"<image>", (unsigned long long)offset, symbol];
    }
    if (CEProbePointerInBundleSegment(pointer, VM_PROT_READ, &image, &offset)) return [NSString stringWithFormat:@"0x%llx data=%@+0x%llx", (unsigned long long)pointer, image ?: @"<image>", (unsigned long long)offset];
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)pointer];
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
    ptrdiff_t offset = ivar_getOffset(ivar) + (ptrdiff_t)(wordIndex * sizeof(uintptr_t)); uintptr_t word = 0; memcpy(&word, (const uint8_t *)object + offset, sizeof(word)); return word;
}

static void CEProbeAppendMethods(NSMutableArray<NSString *> *lines, Class cls, NSString *label) {
    if (!cls) { [lines addObject:[NSString stringWithFormat:@"%@ methods=<class nil>", label]]; return; }
    unsigned int count = 0; Method *methods = class_copyMethodList(cls, &count); [lines addObject:[NSString stringWithFormat:@"%@ class=%@ instanceMethods=%u", label, NSStringFromClass(cls), count]];
    for (unsigned int i = 0; i < count && i < 80; i++) [lines addObject:[NSString stringWithFormat:@"  - %@ | %s", NSStringFromSelector(method_getName(methods[i])), method_getTypeEncoding(methods[i]) ?: ""]];
    free(methods);
}

static void CEProbeAppendExecutableTable(NSMutableArray<NSString *> *lines, uintptr_t table, NSString *label, NSUInteger maxEntries) {
    if (!table || !CEProbeReadable(table, maxEntries * sizeof(uintptr_t))) { [lines addObject:[NSString stringWithFormat:@"%@ table=%@ readable=NO", label, CEProbePointerDescription(table)]]; return; }
    [lines addObject:[NSString stringWithFormat:@"%@ table=%@", label, CEProbePointerDescription(table)]];
    NSUInteger hits = 0;
    for (NSUInteger i = 0; i < maxEntries && hits < 48; i++) {
        uintptr_t value = 0; memcpy(&value, (const void *)(table + i * sizeof(uintptr_t)), sizeof(value));
        NSString *image = nil; uintptr_t offset = 0; if (!CEProbePointerInBundleSegment(value, VM_PROT_EXECUTE, &image, &offset)) continue;
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
        for (uint32_t i = 0; i < imageCount && out.count < 180; i++) {
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
            for (uint32_t s = 0; s < symtab->nsyms && out.count < 180; s++) {
                uint32_t stringIndex = symbols[s].n_un.n_strx; if (!stringIndex || stringIndex >= symtab->strsize) continue; const char *rawName = strings + stringIndex; if (!rawName[0]) continue;
                NSString *raw = [NSString stringWithUTF8String:rawName]; if (!raw.length || !CEProbeInterestingSymbol(raw)) continue;
                NSString *demangled = CEProbeDemangleCString(rawName); [out addObject:[NSString stringWithFormat:@"%@ | raw=%@ | value=0x%llx", demangled, raw, (unsigned long long)symbols[s].n_value]];
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

static void CEProbeAppendFinalStreamClosures(NSMutableArray<NSString *> *lines, uintptr_t object, Class cls) {
    NSArray<NSString *> *fields = @[@"resumeConversationStream", @"initialStream"];
    for (NSString *field in fields) {
        Ivar ivar = class_getInstanceVariable(cls, field.UTF8String); if (!ivar) continue; ptrdiff_t offset = ivar_getOffset(ivar); uintptr_t words[2] = {0, 0}; memcpy(words, (const uint8_t *)object + offset, sizeof(words));
        [lines addObject:[NSString stringWithFormat:@"FINAL-STREAM %@.%@ offset=0x%tx function=%@ context=%@", NSStringFromClass(cls), field, offset, CEProbePointerDescription(words[0]), CEProbePointerDescription(words[1])]];
    }
}

static void CEProbeAppendReachableGraph(NSMutableArray<NSString *> *lines, uintptr_t root) {
    if (!root) return; NSMutableArray<NSDictionary *> *queue = [NSMutableArray arrayWithObject:@{@"ptr": @(root), @"depth": @0}]; NSMutableSet<NSNumber *> *seen = [NSMutableSet set]; NSUInteger emitted = 0;
    while (queue.count && seen.count < 160 && emitted < 80) {
        NSDictionary *entry = queue.firstObject; [queue removeObjectAtIndex:0]; uintptr_t pointer = [entry[@"ptr"] unsignedLongLongValue]; NSUInteger depth = [entry[@"depth"] unsignedIntegerValue]; NSNumber *key = @(pointer); if ([seen containsObject:key]) continue; [seen addObject:key];
        size_t allocation = 0; Class cls = CEProbeHeapClass(pointer, &allocation); if (!cls) continue; NSString *name = NSStringFromClass(cls); if (!CEProbeGraphInterestingClass(name)) continue;
        [lines addObject:[NSString stringWithFormat:@"GRAPH depth=%lu %@", (unsigned long)depth, CEProbePointerDescription(pointer)]]; emitted++;
        if ([name containsString:@"ConversationFinalStream"]) CEProbeAppendFinalStreamClosures(lines, pointer, cls);
        if (depth >= 3) continue; size_t scan = MIN(MIN(allocation, class_getInstanceSize(cls)), (size_t)8192);
        for (size_t offset = 0; offset + sizeof(uintptr_t) <= scan && queue.count < 220; offset += sizeof(uintptr_t)) {
            uintptr_t child = 0; memcpy(&child, (const uint8_t *)pointer + offset, sizeof(child)); size_t childAllocation = 0; Class childClass = CEProbeHeapClass(child, &childAllocation); if (!childClass) continue;
            NSString *childName = NSStringFromClass(childClass); if (!CEProbeGraphInterestingClass(childName)) continue; if (![seen containsObject:@(child)]) [queue addObject:@{@"ptr": @(child), @"depth": @(depth + 1)}];
        }
    }
}

static NSArray<NSString *> *CEProbeCapture(NSString *reason) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array]; UIViewController *messages = CEProbeActiveMessages();
    [lines addObject:[NSString stringWithFormat:@"reason=%@ context=%@ messages=%@ ptr=%p score=%ld", reason ?: @"<nil>", [CEConversationContext shared].conversationID ?: @"<nil>", messages ? NSStringFromClass(messages.class) : @"<nil>", messages, messages ? (long)CEProbeNavigationScore(messages) : -1L]];
    if (!messages) return lines;
    Ivar vmIvar = class_getInstanceVariable(messages.class, "viewModel"); if (!vmIvar) { [lines addObject:@"viewModel ivar=<missing>"]; return lines; }
    uintptr_t vm = 0; memcpy(&vm, (const uint8_t *)(__bridge const void *)messages + ivar_getOffset(vmIvar), sizeof(vm)); NSString *vmDetail = nil; BOOL vmOK = CEProbeValidateObjectPointer(vm, @"ChatGPTMessages.MessagesViewModel", &vmDetail); [lines addObject:[@"viewModel " stringByAppendingString:vmDetail ?: @"<nil>"]]; if (!vmOK) return lines;
    Class vmClass = NSClassFromString(@"ChatGPTMessages.MessagesViewModel"); uintptr_t coordinator = CEProbeReadIvarWord((void *)vm, vmClass, "conversationCoordinator", 0); uintptr_t coordinatorWitness = CEProbeReadIvarWord((void *)vm, vmClass, "conversationCoordinator", 1); NSString *coordDetail = nil; BOOL coordOK = CEProbeValidateObjectPointer(coordinator, @"Conversations.DefaultConversationCoordinator", &coordDetail); [lines addObject:[@"coordinator " stringByAppendingString:coordDetail ?: @"<nil>"]]; [lines addObject:[NSString stringWithFormat:@"coordinatorWitness=%@", CEProbePointerDescription(coordinatorWitness)]]; CEProbeAppendExecutableTable(lines, coordinatorWitness, @"COORD-WITNESS", 96); if (!coordOK) return lines;
    Class coordinatorClass = NSClassFromString(@"Conversations.DefaultConversationCoordinator"); CEProbeAppendMethods(lines, coordinatorClass, @"COORD-METHODS");
    Ivar repositoryIvar = class_getInstanceVariable(coordinatorClass, "conversationRepository"); uintptr_t repository = 0;
    if (repositoryIvar) {
        ptrdiff_t offset = ivar_getOffset(repositoryIvar); [lines addObject:[NSString stringWithFormat:@"conversationRepository offset=0x%tx", offset]];
        for (NSUInteger i = 0; i < 5; i++) { uintptr_t word = 0; memcpy(&word, (const uint8_t *)coordinator + offset + i * sizeof(uintptr_t), sizeof(word)); [lines addObject:[NSString stringWithFormat:@"  repoWord[%lu]=%@", (unsigned long)i, CEProbePointerDescription(word)]]; if (i == 0) repository = word; else { NSString *image = nil; uintptr_t imageOffset = 0; if (CEProbePointerInBundleSegment(word, VM_PROT_READ, &image, &imageOffset) && !CEProbePointerInBundleSegment(word, VM_PROT_EXECUTE, NULL, NULL)) CEProbeAppendExecutableTable(lines, word, [NSString stringWithFormat:@"REPO-TABLE-%lu", (unsigned long)i], 64); } }
    } else [lines addObject:@"conversationRepository ivar=<missing>"];
    size_t repositoryAllocation = 0; Class repositoryClass = CEProbeHeapClass(repository, &repositoryAllocation); if (repositoryClass) CEProbeAppendMethods(lines, repositoryClass, @"REPO-METHODS");
    [lines addObject:@"-- reachable live graph --"]; CEProbeAppendReachableGraph(lines, coordinator);
    [lines addObject:@"-- matching Mach-O symbols --"]; NSArray<NSString *> *symbols = CEProbeInterestingSymbols(); if (symbols.count) [lines addObjectsFromArray:symbols]; else [lines addObject:@"<no matching symbols in LC_SYMTAB>"];
    return lines;
}

void CEInPlaceRecoveryProbe(NSString *reason) {
    void (^work)(void) = ^{
        CERecoveryDiagnosticMark(@"IN-PLACE RECOVERY PROBE"); NSArray<NSString *> *lines = CEProbeCapture(reason ?: @"manual"); CEInPlaceLastSnapshot = [lines componentsJoinedByString:@"\n"];
        for (NSString *line in lines) CERecoveryDiagnosticLog(@"INPLACE29", @"%@", line);
    };
    if (NSThread.isMainThread) work(); else dispatch_async(dispatch_get_main_queue(), work);
}

NSString *CEInPlaceRecoveryProbeSnapshot(void) { return CEInPlaceLastSnapshot ?: @"<not captured>"; }
