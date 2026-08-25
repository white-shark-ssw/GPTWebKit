#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Network/CEAPIClient.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"

static NSUInteger CEUsageGeneration = 0;
static dispatch_queue_t CEUsageQueue;
static NSMutableDictionary<NSString *, NSDate *> *CEUsageFallbackFetchDates;
static NSMutableSet<NSString *> *CEUsageFallbackInFlight;
static NSString *CEUsageDisplayedConversationID = nil;

static BOOL CEUsageIsCJK(unichar c) { return (c >= 0x3400 && c <= 0x9FFF) || (c >= 0x3040 && c <= 0x30FF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF); }

static double CEUsageEstimatedTokensForString(NSString *text) {
    if (!text.length) return 0;
    NSUInteger cjk = 0, asciiWord = 0, asciiPunctuation = 0, other = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (CEUsageIsCJK(c)) cjk++;
        else if (c < 128) {
            if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) asciiWord++;
            else if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) asciiPunctuation++;
        } else other++;
    }
    return cjk * 1.05 + ceil(asciiWord / 4.0) + asciiPunctuation * 0.45 + other * 0.85;
}

static double CEUsageEstimatedTokensForObject(id value, NSUInteger depth) {
    if (!value || depth > 10 || value == NSNull.null) return 0;
    if ([value isKindOfClass:NSString.class]) return CEUsageEstimatedTokensForString(value);
    if ([value isKindOfClass:NSArray.class]) { double total = 1.0; for (id child in (NSArray *)value) total += CEUsageEstimatedTokensForObject(child, depth + 1) + 0.35; return total; }
    if ([value isKindOfClass:NSDictionary.class]) {
        double total = 1.5;
        for (id key in (NSDictionary *)value) { if ([key isKindOfClass:NSString.class]) total += CEUsageEstimatedTokensForString(key) * 0.65; total += CEUsageEstimatedTokensForObject(((NSDictionary *)value)[key], depth + 1) + 0.45; }
        return total;
    }
    if ([value respondsToSelector:@selector(stringValue)]) return CEUsageEstimatedTokensForString([value stringValue]);
    return 0;
}

static NSDictionary *CEUsageConversationContainer(id root) {
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dictionary = root;
    if ([dictionary[@"mapping"] isKindOfClass:NSDictionary.class]) return dictionary;
    NSDictionary *conversation = [dictionary[@"conversation"] isKindOfClass:NSDictionary.class] ? dictionary[@"conversation"] : nil;
    return [conversation[@"mapping"] isKindOfClass:NSDictionary.class] ? conversation : nil;
}

static NSString *CEUsageModelString(id raw) {
    if (![raw isKindOfClass:NSString.class]) return nil;
    NSString *value = [(NSString *)raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.length ? value : nil;
}

static NSString *CEUsageModelFromDictionary(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *key in @[@"model_slug", @"default_model_slug", @"model", @"model_name", @"model_id"]) { NSString *value = CEUsageModelString(dictionary[key]); if (value.length) return value; }
    return nil;
}

static NSString *CEUsageCurrentModel(NSDictionary *root, NSDictionary *container, NSDictionary *mapping, NSString *currentNode) {
    NSString *nodeID = currentNode; NSMutableSet<NSString *> *visited = [NSMutableSet set]; NSUInteger scanned = 0;
    while (nodeID.length && scanned < 64 && ![visited containsObject:nodeID]) {
        [visited addObject:nodeID]; scanned++;
        NSDictionary *node = [mapping[nodeID] isKindOfClass:NSDictionary.class] ? mapping[nodeID] : nil; if (!node) break;
        NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
        NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : nil;
        NSString *model = CEUsageModelFromDictionary(metadata) ?: CEUsageModelFromDictionary(message);
        if (model.length && ![[model lowercaseString] isEqualToString:@"auto"]) return model;
        nodeID = [node[@"parent"] isKindOfClass:NSString.class] ? node[@"parent"] : nil;
    }
    NSString *model = CEUsageModelFromDictionary(container); if (model.length && ![[model lowercaseString] isEqualToString:@"auto"]) return model;
    model = CEUsageModelFromDictionary(root); if (model.length && ![[model lowercaseString] isEqualToString:@"auto"]) return model;
    return nil;
}

static NSUInteger CEUsageExplicitContextCapacity(id value, NSUInteger depth) {
    if (!value || depth > 5 || value == NSNull.null) return 0;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = value;
        for (NSString *key in @[@"context_window", @"context_window_size", @"max_context_tokens", @"max_context_length"]) {
            id raw = dictionary[key]; NSUInteger candidate = [raw respondsToSelector:@selector(unsignedIntegerValue)] ? [raw unsignedIntegerValue] : 0;
            if (candidate >= 16000 && candidate <= 2000000) return candidate;
        }
        for (id key in dictionary) {
            if ([key isKindOfClass:NSString.class] && [[(NSString *)key lowercaseString] isEqualToString:@"mapping"]) continue;
            id child = dictionary[key];
            if (![child isKindOfClass:NSDictionary.class] && ![child isKindOfClass:NSArray.class]) continue;
            NSUInteger candidate = CEUsageExplicitContextCapacity(child, depth + 1); if (candidate) return candidate;
        }
    } else if ([value isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)value) { NSUInteger candidate = CEUsageExplicitContextCapacity(child, depth + 1); if (candidate) return candidate; }
    }
    return 0;
}

static NSUInteger CEUsageCapacityForModel(NSString *model, NSString **sourceOut) {
    NSString *lower = model.lowercaseString ?: @"";
    if ([lower containsString:@"gpt-5.6"] || [lower containsString:@"gpt-5-6"]) { if (sourceOut) *sourceOut = @"model:gpt-5.6=1.05m"; return 1050000; }
    if ([lower containsString:@"gpt-5.5"] || [lower containsString:@"gpt-5-5"]) { if (sourceOut) *sourceOut = @"model:gpt-5.5=1.05m"; return 1050000; }
    if ([lower containsString:@"gpt-5.4-mini"] || [lower containsString:@"gpt-5-4-mini"] || [lower containsString:@"gpt-5.4-nano"] || [lower containsString:@"gpt-5-4-nano"]) { if (sourceOut) *sourceOut = @"model:gpt-5.4-mini/nano=400k"; return 400000; }
    if ([lower containsString:@"gpt-5.4"] || [lower containsString:@"gpt-5-4"]) { if (sourceOut) *sourceOut = @"model:gpt-5.4=1.05m"; return 1050000; }
    if ([lower containsString:@"gpt-5.3-chat"] || [lower containsString:@"gpt-5-3-chat"] || [lower containsString:@"gpt-5-chat-latest"]) { if (sourceOut) *sourceOut = @"model:gpt-5-chat=128k"; return 128000; }
    if ([lower containsString:@"chat-latest"]) { if (sourceOut) *sourceOut = @"model:chat-latest=400k"; return 400000; }
    if ([lower containsString:@"gpt-5.3-codex"] || [lower containsString:@"gpt-5-3-codex"]) { if (sourceOut) *sourceOut = @"model:gpt-5.3-codex=400k"; return 400000; }
    if ([lower containsString:@"gpt-5.3"] || [lower containsString:@"gpt-5-3"] || [lower containsString:@"gpt-5.2"] || [lower containsString:@"gpt-5-2"] || [lower containsString:@"gpt-5.1"] || [lower containsString:@"gpt-5-1"] || [lower hasPrefix:@"gpt-5"]) { if (sourceOut) *sourceOut = @"model:gpt-5-family=400k"; return 400000; }
    if ([lower containsString:@"gpt-4.1"] || [lower containsString:@"gpt-4-1"]) { if (sourceOut) *sourceOut = @"model:gpt-4.1≈1m"; return 1047576; }
    if ([lower containsString:@"gpt-4o"] || [lower containsString:@"gpt-4-o"]) { if (sourceOut) *sourceOut = @"model:gpt-4o=128k"; return 128000; }
    if ([lower hasPrefix:@"o3"] || [lower hasPrefix:@"o4"]) { if (sourceOut) *sourceOut = @"model:o3/o4=200k"; return 200000; }
    if (sourceOut) *sourceOut = model.length ? [NSString stringWithFormat:@"unknown-model:%@ fallback=128k", model] : @"model-unavailable fallback=128k";
    return 128000;
}

static NSUInteger CEUsageEstimatePercent(NSData *data, NSUInteger *estimatedTokensOut, NSUInteger *capacityOut, NSUInteger *messagesOut, NSString **modelOut, NSString **capacitySourceOut) {
    if (estimatedTokensOut) *estimatedTokensOut = 0; if (capacityOut) *capacityOut = 0; if (messagesOut) *messagesOut = 0; if (modelOut) *modelOut = nil; if (capacitySourceOut) *capacitySourceOut = nil;
    if (!data.length) return NSNotFound;
    NSError *jsonError = nil; id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    NSDictionary *root = [rootObject isKindOfClass:NSDictionary.class] ? rootObject : nil;
    NSDictionary *container = CEUsageConversationContainer(rootObject); if (!root || !container) return NSNotFound;
    NSDictionary *mapping = [container[@"mapping"] isKindOfClass:NSDictionary.class] ? container[@"mapping"] : nil;
    NSString *currentNode = [container[@"current_node"] isKindOfClass:NSString.class] ? container[@"current_node"] : nil;
    if (!mapping.count || !currentNode.length) return NSNotFound;

    NSString *model = CEUsageCurrentModel(root, container, mapping, currentNode);
    double tokens = 0; NSUInteger messages = 0; NSMutableSet<NSString *> *visited = [NSMutableSet set]; NSString *nodeID = currentNode;
    while (nodeID.length && messages < 10000 && ![visited containsObject:nodeID]) {
        [visited addObject:nodeID];
        NSDictionary *node = [mapping[nodeID] isKindOfClass:NSDictionary.class] ? mapping[nodeID] : nil; if (!node) break;
        NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
        if (message) {
            tokens += CEUsageEstimatedTokensForObject(message[@"content"], 0) + 10.0;
            NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : nil;
            NSString *role = [author[@"role"] isKindOfClass:NSString.class] ? author[@"role"] : nil; if (role.length) tokens += CEUsageEstimatedTokensForString(role);
            NSString *name = [author[@"name"] isKindOfClass:NSString.class] ? author[@"name"] : nil; if (name.length) tokens += CEUsageEstimatedTokensForString(name);
            NSString *recipient = [message[@"recipient"] isKindOfClass:NSString.class] ? message[@"recipient"] : nil; if (recipient.length) tokens += CEUsageEstimatedTokensForString(recipient);
            messages++;
        }
        nodeID = [node[@"parent"] isKindOfClass:NSString.class] ? node[@"parent"] : nil;
    }

    NSString *capacitySource = nil; NSUInteger capacity = CEUsageExplicitContextCapacity(root, 0);
    if (capacity) capacitySource = @"conversation-json-explicit"; else capacity = CEUsageCapacityForModel(model, &capacitySource);
    NSUInteger estimated = (NSUInteger)llround(tokens);
    NSUInteger percent = capacity ? (NSUInteger)llround((double)estimated * 100.0 / (double)capacity) : 0; percent = MIN(percent, 100);
    if (estimatedTokensOut) *estimatedTokensOut = estimated; if (capacityOut) *capacityOut = capacity; if (messagesOut) *messagesOut = messages; if (modelOut) *modelOut = model; if (capacitySourceOut) *capacitySourceOut = capacitySource;
    return percent;
}

static id CEUsageFloatingController(void) {
    Class cls = NSClassFromString(@"CEFloatingButtonController"); SEL shared = NSSelectorFromString(@"shared");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, shared);
}

static UIButton *CEUsageFloatingButton(void) {
    id controller = CEUsageFloatingController(); if (!controller) return nil;
    UIButton *button = nil; @try { button = [controller valueForKey:@"button"]; } @catch (__unused NSException *exception) {}
    return [button isKindOfClass:UIButton.class] ? button : nil;
}

static void CEUsageApplyButtonStyle(UIButton *button, NSString *percentText) {
    if (!button) return;
    CGRect frame = button.frame; CGFloat oldWidth = frame.size.width; frame.size.width = 60.0;
    if (button.superview && oldWidth > 0 && fabs(oldWidth - frame.size.width) > 0.5) frame.origin.x -= frame.size.width - oldWidth;
    button.frame = frame; button.layer.cornerRadius = 14;
    [button setImage:nil forState:UIControlStateNormal]; [button setTitle:percentText forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBold]; button.titleLabel.adjustsFontSizeToFitWidth = YES; button.titleLabel.minimumScaleFactor = 0.78; button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter; button.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6); button.imageEdgeInsets = UIEdgeInsetsZero; button.titleEdgeInsets = UIEdgeInsetsZero;
    button.accessibilityLabel = [NSString stringWithFormat:@"ChatGPTEnhancer 会话工具，当前会话占用约 %@", percentText];
}

static void CEUsageComputeData(NSData *data, NSString *conversationID, NSString *source) {
    if (!data.length || !conversationID.length) return;
    NSUInteger generation = ++CEUsageGeneration;
    dispatch_async(CEUsageQueue, ^{
        NSUInteger estimated = 0, capacity = 0, messages = 0; NSString *model = nil, *capacitySource = nil;
        NSUInteger percent = CEUsageEstimatePercent(data, &estimated, &capacity, &messages, &model, &capacitySource);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != CEUsageGeneration || ![[CEConversationContext shared].conversationID isEqualToString:conversationID]) return;
            UIButton *button = CEUsageFloatingButton(); if (!button) return;
            NSString *text = percent == NSNotFound ? @"--%" : [NSString stringWithFormat:@"%lu%%", (unsigned long)percent];
            CEUsageApplyButtonStyle(button, text); CEUsageDisplayedConversationID = [conversationID copy];
            CERecoveryDiagnosticLog(@"USAGE", @"conversation=%@ model=%@ estimatedTokens=%lu capacity=%lu capacitySource=%@ messages=%lu percent=%@ source=%@ bytes=%lu", conversationID, model ?: @"<nil>", (unsigned long)estimated, (unsigned long)capacity, capacitySource ?: @"<nil>", (unsigned long)messages, text, source ?: @"unknown", (unsigned long)data.length);
        });
    });
}

static BOOL CEUsageMayFallbackFetch(NSString *conversationID) {
    if (!conversationID.length || ![CEAPIClient shared].isReady || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    @synchronized (CEUsageFallbackFetchDates) {
        if ([CEUsageFallbackInFlight containsObject:conversationID]) return NO;
        NSDate *last = CEUsageFallbackFetchDates[conversationID]; if (last && [NSDate.date timeIntervalSinceDate:last] < 60.0) return NO;
        CEUsageFallbackFetchDates[conversationID] = NSDate.date; [CEUsageFallbackInFlight addObject:conversationID]; return YES;
    }
}

static void CEUsageFallbackFetch(NSString *conversationID) {
    if (!CEUsageMayFallbackFetch(conversationID)) return;
    NSString *escaped = [conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]; NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", escaped];
    CERecoveryDiagnosticLog(@"USAGE", @"cache miss; one-shot fallback GET conversation=%@", conversationID);
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        @synchronized (CEUsageFallbackFetchDates) { [CEUsageFallbackInFlight removeObject:conversationID]; }
        if (error || response.statusCode < 200 || response.statusCode >= 300 || !data.length) { CERecoveryDiagnosticLog(@"USAGE", @"fallback GET failed conversation=%@ status=%ld error=%@", conversationID, (long)response.statusCode, error.localizedDescription ?: @"<nil>"); return; }
        CEUsageComputeData(data, conversationID, @"one-shot-current-conversation-GET");
    }];
}

static void CEUsageRefreshCurrent(BOOL allowFallback) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIButton *button = CEUsageFloatingButton(); if (!button) return;
        NSString *conversationID = [[CEConversationContext shared].conversationID copy];
        if (!conversationID.length) { CEUsageDisplayedConversationID = nil; CEUsageApplyButtonStyle(button, @"--%"); return; }
        if (![CEUsageDisplayedConversationID isEqualToString:conversationID]) CEUsageApplyButtonStyle(button, @"--%");
        NSData *data = [[CECatalog shared] conversationDataForID:conversationID]; if (data.length) { CEUsageComputeData(data, conversationID, @"catalog-full-conversation"); return; }
        if (!allowFallback) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![[CEConversationContext shared].conversationID isEqualToString:conversationID]) return;
            NSData *lateData = [[CECatalog shared] conversationDataForID:conversationID]; if (lateData.length) CEUsageComputeData(lateData, conversationID, @"catalog-delayed-full-conversation"); else CEUsageFallbackFetch(conversationID);
        });
    });
}

__attribute__((constructor)) static void CEConversationUsageIndicatorEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        CEUsageQueue = dispatch_queue_create("com.whiteshark.chatgptenhancer.usage", DISPATCH_QUEUE_SERIAL); CEUsageFallbackFetchDates = [NSMutableDictionary dictionary]; CEUsageFallbackInFlight = [NSMutableSet set];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:CEConversationContextDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { CEUsageRefreshCurrent(YES); }];
        [center addObserverForName:CECatalogDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { CEUsageRefreshCurrent(NO); }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { CEUsageRefreshCurrent(YES); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEUsageRefreshCurrent(YES); });
    }
}
