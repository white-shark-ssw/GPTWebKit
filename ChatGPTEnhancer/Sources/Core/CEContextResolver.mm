#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CECore.h"
#import "../Storage/CECatalog.h"

static void CECollectActuallyVisibleStrings(UIView *view, NSUInteger depth, NSMutableOrderedSet<NSString *> *output) {
    if (!view || depth > 8 || view.hidden || view.alpha < 0.02 || !view.window) return;
    CGRect frame = [view convertRect:view.bounds toView:view.window];
    if (CGRectIsEmpty(frame) || !CGRectIntersectsRect(frame, view.window.bounds)) return;
    BOOL syntheticConversationTitle = [view isKindOfClass:UILabel.class] && [view viewWithTag:CESyntheticConversationTitleMarkerTag] != nil;
    if (!syntheticConversationTitle) {
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
    }
    for (UIView *child in view.subviews) CECollectActuallyVisibleStrings(child, depth + 1, output);
}

NSString *CERefreshVisibleConversationContext(void) {
    UIWindow *window = CEKeyWindow(); if (!window) return nil;
    NSMutableOrderedSet<NSString *> *strings = [NSMutableOrderedSet orderedSet]; CECollectActuallyVisibleStrings(window, 0, strings);

    NSMutableDictionary<NSString *, CEConversationRecord *> *explicitIDs = [NSMutableDictionary dictionary];
    for (NSString *value in strings) {
        NSString *conversationID = CEExtractConversationIDFromString(value);
        CEConversationRecord *record = conversationID.length ? [[CECatalog shared] recordForID:conversationID] : nil;
        if (record.conversationID.length) explicitIDs[record.conversationID] = record;
    }
    if (explicitIDs.count == 1) {
        CEConversationRecord *record = explicitIDs.allValues.firstObject;
        [[CEConversationContext shared] setConversationID:record.conversationID title:record.title];
        return record.conversationID;
    }
    if (explicitIDs.count > 1) return nil;

    NSMutableDictionary<NSString *, CEConversationRecord *> *titleMatches = [NSMutableDictionary dictionary];
    for (NSString *value in strings) {
        NSArray<CEConversationRecord *> *matches = [[CECatalog shared] recordsMatchingTitle:value];
        if (matches.count == 1) {
            CEConversationRecord *record = matches.firstObject;
            if (record.conversationID.length) titleMatches[record.conversationID] = record;
        }
    }
    if (titleMatches.count != 1) return nil;
    CEConversationRecord *record = titleMatches.allValues.firstObject;
    [[CEConversationContext shared] setConversationID:record.conversationID title:record.title];
    return record.conversationID;
}

@interface CEContextResolver : NSObject
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation CEContextResolver
+ (instancetype)shared { static CEContextResolver *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [CEContextResolver new]; }); return value; }

- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resolveNow) name:CECatalogDidChangeNotification object:nil];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(resolveNow) userInfo:nil repeats:YES];
        [self resolveNow];
    });
}

- (void)resolveNow { CERefreshVisibleConversationContext(); }
@end

__attribute__((constructor)) static void CEContextResolverEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[CEContextResolver shared] start];
        });
    }
}
