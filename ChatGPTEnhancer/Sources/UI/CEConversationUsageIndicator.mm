#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"

static NSUInteger CEUsageGeneration = 0;
static dispatch_queue_t CEUsageQueue;

static BOOL CEUsageIsCJK(unichar c) {
    return (c >= 0x3400 && c <= 0x9FFF) || (c >= 0x3040 && c <= 0x30FF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF);
}

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
    if ([value isKindOfClass:NSArray.class]) { double total = 0; for (id child in (NSArray *)value) total += CEUsageEstimatedTokensForObject(child, depth + 1); return total; }
    if ([value isKindOfClass:NSDictionary.class]) { double total = 0; for (id child in [(NSDictionary *)value allValues]) total += CEUsageEstimatedTokensForObject(child, depth + 1); return total; }
    return 0;
}

static NSUInteger CEUsageContextCapacityFromObject(id value, NSUInteger depth) {
    if (!value || depth > 8 || value == NSNull.null) return 0;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = value;
        for (NSString *key in @[@"context_window", @"context_window_size", @"max_context_tokens", @"max_context_length"]) {
            id raw = dictionary[key]; NSUInteger candidate = [raw respondsToSelector:@selector(unsignedIntegerValue)] ? [raw unsignedIntegerValue] : 0;
            if (candidate >= 16000 && candidate <= 2000000) return candidate;
        }
        for (id child in dictionary.allValues) { NSUInteger candidate = CEUsageContextCapacityFromObject(child, depth + 1); if (candidate) return candidate; }
    } else if ([value isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)value) { NSUInteger candidate = CEUsageContextCapacityFromObject(child, depth + 1); if (candidate) return candidate; }
    }
    return 0;
}

static NSDictionary *CEUsageConversationContainer(id root) {
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dictionary = root;
    if ([dictionary[@"mapping"] isKindOfClass:NSDictionary.class]) return dictionary;
    NSDictionary *conversation = [dictionary[@"conversation"] isKindOfClass:NSDictionary.class] ? dictionary[@"conversation"] : nil;
    return [conversation[@"mapping"] isKindOfClass:NSDictionary.class] ? conversation : nil;
}

static NSUInteger CEUsageEstimatePercent(NSData *data, NSUInteger *estimatedTokensOut, NSUInteger *capacityOut) {
    if (estimatedTokensOut) *estimatedTokensOut = 0;
    if (capacityOut) *capacityOut = 0;
    if (!data.length) return NSNotFound;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *container = CEUsageConversationContainer(root); if (!container) return NSNotFound;
    NSDictionary *mapping = [container[@"mapping"] isKindOfClass:NSDictionary.class] ? container[@"mapping"] : nil;
    NSString *nodeID = [container[@"current_node"] isKindOfClass:NSString.class] ? container[@"current_node"] : nil;
    if (!mapping.count || !nodeID.length) return NSNotFound;

    double tokens = 0; NSUInteger messages = 0; NSMutableSet<NSString *> *visited = [NSMutableSet set];
    while (nodeID.length && messages < 10000 && ![visited containsObject:nodeID]) {
        [visited addObject:nodeID];
        NSDictionary *node = [mapping[nodeID] isKindOfClass:NSDictionary.class] ? mapping[nodeID] : nil; if (!node) break;
        NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
        if (message) {
            id content = message[@"content"]; tokens += CEUsageEstimatedTokensForObject(content, 0) + 8.0;
            NSString *recipient = [message[@"recipient"] isKindOfClass:NSString.class] ? message[@"recipient"] : nil; if (recipient.length) tokens += CEUsageEstimatedTokensForString(recipient);
            messages++;
        }
        nodeID = [node[@"parent"] isKindOfClass:NSString.class] ? node[@"parent"] : nil;
    }

    NSUInteger capacity = CEUsageContextCapacityFromObject(root, 0); if (!capacity) capacity = 128000;
    NSUInteger estimated = (NSUInteger)llround(tokens);
    NSUInteger percent = capacity ? (NSUInteger)llround((double)estimated * 100.0 / (double)capacity) : 0;
    percent = MIN(percent, 100);
    if (estimatedTokensOut) *estimatedTokensOut = estimated;
    if (capacityOut) *capacityOut = capacity;
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
    CGRect frame = button.frame; CGFloat oldWidth = frame.size.width; frame.size.width = 76.0;
    if (button.superview && oldWidth > 0) frame.origin.x -= frame.size.width - oldWidth;
    button.frame = frame; button.layer.cornerRadius = 14;
    UIImageSymbolConfiguration *gearConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [button setImage:[[UIImage systemImageNamed:@"gearshape.fill"] imageWithConfiguration:gearConfig] forState:UIControlStateNormal];
    [button setTitle:percentText forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    button.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 4);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -2);
    button.accessibilityLabel = [NSString stringWithFormat:@"ChatGPTEnhancer 会话工具，当前会话占用约 %@", percentText];
}

static void CEUsageScheduleRefresh(void) {
    NSUInteger generation = ++CEUsageGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIButton *button = CEUsageFloatingButton(); if (!button) return;
        CEUsageApplyButtonStyle(button, @"--%");
        NSString *conversationID = [[CEConversationContext shared].conversationID copy]; if (!conversationID.length) return;
        NSData *data = [[CECatalog shared] conversationDataForID:conversationID]; if (!data.length) return;
        dispatch_async(CEUsageQueue, ^{
            NSUInteger estimated = 0, capacity = 0; NSUInteger percent = CEUsageEstimatePercent(data, &estimated, &capacity);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != CEUsageGeneration || ![[CEConversationContext shared].conversationID isEqualToString:conversationID]) return;
                UIButton *currentButton = CEUsageFloatingButton(); if (!currentButton) return;
                NSString *text = percent == NSNotFound ? @"--%" : [NSString stringWithFormat:@"%lu%%", (unsigned long)percent];
                CEUsageApplyButtonStyle(currentButton, text);
                CERecoveryDiagnosticLog(@"USAGE", @"conversation=%@ estimatedTokens=%lu capacity=%lu percent=%@ source=%@", conversationID, (unsigned long)estimated, (unsigned long)capacity, text, capacity == 128000 ? @"fallback-128k-or-json-128k" : @"conversation-json");
            });
        });
    });
}

__attribute__((constructor)) static void CEConversationUsageIndicatorEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        CEUsageQueue = dispatch_queue_create("com.whiteshark.chatgptenhancer.usage", DISPATCH_QUEUE_SERIAL);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:CEConversationContextDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { CEUsageScheduleRefresh(); }];
        [center addObserverForName:CECatalogDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { CEUsageScheduleRefresh(); }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { CEUsageScheduleRefresh(); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CEUsageScheduleRefresh(); });
    }
}
