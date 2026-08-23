#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CECore.h"
#import "../Storage/CECatalog.h"

static BOOL CEContextURLLooksRelevant(NSURL *url) {
    NSString *host = url.host.lowercaseString ?: @"";
    if (![host containsString:@"chatgpt"] && ![host containsString:@"openai"]) return NO;
    NSString *path = url.path.lowercaseString ?: @"";
    return [path containsString:@"conversation"] || [path containsString:@"backend-api"];
}

@implementation NSURLSessionTask (ChatGPTEnhancerContextProbe)
- (void)ce_context_resume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    NSURL *url = request.URL;
    if (url && CEContextURLLooksRelevant(url)) {
        NSString *conversationID = CEExtractConversationIDFromString(url.absoluteString);
        if (conversationID.length) [[CEConversationContext shared] setConversationID:conversationID title:nil];
    }
    [self ce_context_resume];
}
@end

static void CECollectActuallyVisibleStrings(UIView *view, NSUInteger depth, NSMutableOrderedSet<NSString *> *output) {
    if (!view || depth > 8 || view.hidden || view.alpha < 0.02 || !view.window) return;
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    if (view.accessibilityIdentifier.length) [values addObject:view.accessibilityIdentifier];
    if (view.accessibilityLabel.length) [values addObject:view.accessibilityLabel];
    if ([view.accessibilityValue isKindOfClass:NSString.class] && [(NSString *)view.accessibilityValue length]) [values addObject:(NSString *)view.accessibilityValue];
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) [values addObject:((UILabel *)view).text];
    if ([view isKindOfClass:UIButton.class]) {
        NSString *title = [((UIButton *)view) titleForState:UIControlStateNormal];
        if (title.length) [values addObject:title];
    }
    for (NSString *value in values) {
        NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length && trimmed.length < 240) [output addObject:trimmed];
    }
    for (UIView *child in view.subviews) CECollectActuallyVisibleStrings(child, depth + 1, output);
}

@interface CEContextResolver : NSObject
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation CEContextResolver
+ (instancetype)shared { static CEContextResolver *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [CEContextResolver new]; }); return value; }

- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CESwizzleInstanceMethod(NSURLSessionTask.class, @selector(resume), @selector(ce_context_resume));
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resolveNow) name:CECatalogDidChangeNotification object:nil];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(resolveNow) userInfo:nil repeats:YES];
        [self resolveNow];
    });
}

- (void)resolveNow {
    if ([CEConversationContext shared].conversationID.length) return;
    UIWindow *window = CEKeyWindow();
    if (!window) return;
    NSMutableOrderedSet<NSString *> *strings = [NSMutableOrderedSet orderedSet];
    CECollectActuallyVisibleStrings(window, 0, strings);

    for (NSString *value in strings) {
        NSString *conversationID = CEExtractConversationIDFromString(value);
        CEConversationRecord *record = conversationID.length ? [[CECatalog shared] recordForID:conversationID] : nil;
        if (record.conversationID.length) {
            [[CEConversationContext shared] setConversationID:record.conversationID title:record.title];
            return;
        }
    }

    NSMutableDictionary<NSString *, CEConversationRecord *> *unique = [NSMutableDictionary dictionary];
    for (NSString *value in strings) {
        NSArray<CEConversationRecord *> *matches = [[CECatalog shared] recordsMatchingTitle:value];
        if (matches.count == 1) {
            CEConversationRecord *record = matches.firstObject;
            if (record.conversationID.length) unique[record.conversationID] = record;
        }
    }
    if (unique.count == 1) {
        CEConversationRecord *record = unique.allValues.firstObject;
        [[CEConversationContext shared] setConversationID:record.conversationID title:record.title];
    }
}
@end

__attribute__((constructor)) static void CEContextResolverEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[CEContextResolver shared] start];
        });
    }
}
