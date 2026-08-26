#import "CEEnhancerUI.h"
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"
#import "../Diagnostics/CEDiagnostics.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import <objc/runtime.h>

static __weak UIView *CELastTouchedView = nil;
static NSDate *CELastTouchDate = nil;
static NSString *CELastTouchedTitle = nil;
static BOOL CEMenuBuildGuard = NO;
static NSString * const CEExtensionMenuIdentifier = @"com.whiteshark.chatgptenhancer.section";
static NSInteger const CEProjectHeaderMarkerTag = 0x43454844;

static void CECollectMenuTitles(NSArray<UIMenuElement *> *elements, NSMutableArray<NSString *> *out) {
    for (UIMenuElement *element in elements) {
        if ([element isKindOfClass:UIAction.class]) { NSString *title = ((UIAction *)element).title; if (title.length) [out addObject:title]; }
        else if ([element isKindOfClass:UIMenu.class]) CECollectMenuTitles(((UIMenu *)element).children, out);
    }
}

static BOOL CEHasExtensionSection(NSArray<UIMenuElement *> *elements) {
    for (UIMenuElement *element in elements) {
        if ([element isKindOfClass:UIMenu.class]) {
            UIMenu *menu = (UIMenu *)element;
            if ([menu.identifier isEqualToString:CEExtensionMenuIdentifier]) return YES;
            if (CEHasExtensionSection(menu.children)) return YES;
        }
    }
    return NO;
}

static BOOL CELooksLikeConversationMenu(NSArray<UIMenuElement *> *elements) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array]; CECollectMenuTitles(elements, titles);
    NSArray<NSArray<NSString *> *> *signals = @[
        @[@"rename", @"重命名", @"重新命名"], @[@"archive", @"归档"], @[@"delete", @"删除"],
        @[@"move", @"移至", @"移动", @"移除"], @[@"share", @"共享", @"分享"], @[@"pin", @"置顶"]
    ];
    NSUInteger score = 0;
    for (NSArray<NSString *> *group in signals) {
        BOOL hit = NO;
        for (NSString *title in titles) {
            NSString *lower = title.lowercaseString;
            for (NSString *needle in group) if ([lower containsString:needle.lowercaseString]) { hit = YES; break; }
            if (hit) break;
        }
        if (hit) score++;
    }
    return score >= 2;
}

static NSString *CEQuotedConversationTitle(NSString *text) {
    if (!text.length) return nil;
    NSArray<NSArray<NSString *> *> *pairs = @[
        @[@"给“", @"”发送消息"], @[@"给\"", @"\"发送消息"], @[@"给「", @"」发送消息"],
        @[@"Message “", @"”"], @[@"Message \"", @"\""]
    ];
    for (NSArray<NSString *> *pair in pairs) {
        NSRange start = [text rangeOfString:pair[0]]; if (start.location == NSNotFound) continue;
        NSUInteger bodyStart = NSMaxRange(start);
        NSRange search = NSMakeRange(bodyStart, text.length - bodyStart);
        NSRange end = [text rangeOfString:pair[1] options:0 range:search];
        if (end.location == NSNotFound || end.location <= bodyStart) continue;
        NSString *title = [[text substringWithRange:NSMakeRange(bodyStart, end.location - bodyStart)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (title.length >= 2 && title.length <= 160) return title;
    }
    return nil;
}

static NSString *CEBestTitleFromView(UIView *view) {
    if (!view) return nil;
    NSArray<NSString *> *strings = CECollectVisibleStrings(view, 5);
    for (NSString *text in strings) { NSString *title = CEQuotedConversationTitle(text); if (title.length) return title; }
    for (NSString *text in strings) {
        NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trim.length < 2 || trim.length > 120 || [trim containsString:@"\n"]) continue;
        NSString *lower = trim.lowercaseString;
        if ([lower isEqualToString:@"chatgpt"] || [trim isEqualToString:@"聊天"] || [trim isEqualToString:@"新聊天"] || [trim isEqualToString:@"重命名"] || [trim isEqualToString:@"删除"] || [trim isEqualToString:@"归档"] || [trim isEqualToString:@"置顶"]) continue;
        return trim;
    }
    return nil;
}

static NSString *CECatalogTitleFromAccessibilityText(NSString *text) {
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trim.length < 2 || trim.length > 240) return nil;
    if ([[CECatalog shared] recordsMatchingTitle:trim].count) return trim;
    NSString *quoted = CEQuotedConversationTitle(trim);
    if (quoted.length && [[CECatalog shared] recordsMatchingTitle:quoted].count) return quoted;
    NSArray<NSString *> *suffixes = @[@"，按钮", @", button", @" 按钮"];
    for (NSString *suffix in suffixes) {
        if (![trim.lowercaseString hasSuffix:suffix.lowercaseString] || trim.length <= suffix.length) continue;
        NSString *candidate = [[trim substringToIndex:trim.length - suffix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (candidate.length && [[CECatalog shared] recordsMatchingTitle:candidate].count) return candidate;
    }
    return nil;
}

static void CEConsiderAccessibilityObject(id object, CGPoint screenPoint, NSString **bestTitle, CGFloat *bestScore) {
    if (!object) return;
    if ([object isKindOfClass:UILabel.class] && [(UILabel *)object viewWithTag:CEProjectHeaderMarkerTag]) return;
    CGRect frame = CGRectNull;
    @try {
        if ([object respondsToSelector:@selector(accessibilityFrame)]) frame = [object accessibilityFrame];
    } @catch (__unused NSException *exception) {}
    if (CGRectIsNull(frame) || CGRectIsInfinite(frame) || CGRectIsEmpty(frame)) return;

    CGFloat distanceY = 0;
    if (screenPoint.y < CGRectGetMinY(frame)) distanceY = CGRectGetMinY(frame) - screenPoint.y;
    else if (screenPoint.y > CGRectGetMaxY(frame)) distanceY = screenPoint.y - CGRectGetMaxY(frame);
    BOOL near = CGRectContainsPoint(CGRectInset(frame, -12, -8), screenPoint) || distanceY <= 12;
    if (!near) return;

    NSArray<NSString *> *texts = @[
        [object respondsToSelector:@selector(accessibilityLabel)] ? ([object accessibilityLabel] ?: @"") : @"",
        [object respondsToSelector:@selector(accessibilityValue)] ? ([object accessibilityValue] ?: @"") : @"",
        [object respondsToSelector:@selector(accessibilityIdentifier)] ? ([object accessibilityIdentifier] ?: @"") : @""
    ];
    for (NSString *text in texts) {
        NSString *title = CECatalogTitleFromAccessibilityText(text);
        if (!title.length) continue;
        CGFloat area = MAX(frame.size.width * frame.size.height, 1);
        CGFloat score = CGRectContainsPoint(frame, screenPoint) ? (1000000.0 - MIN(area, 900000.0)) : (1000.0 - distanceY * 20.0);
        if (!*bestTitle || score > *bestScore) { *bestTitle = title; *bestScore = score; }
    }
}

static void CEFindAccessibilityTitleRecursive(UIView *view, CGPoint screenPoint, NSUInteger depth, NSString **bestTitle, CGFloat *bestScore) {
    if (!view || depth > 14 || view.hidden || view.alpha < 0.01) return;
    CEConsiderAccessibilityObject(view, screenPoint, bestTitle, bestScore);
    NSArray *elements = nil;
    @try { elements = view.accessibilityElements; } @catch (__unused NSException *exception) {}
    for (id element in elements ?: @[]) CEConsiderAccessibilityObject(element, screenPoint, bestTitle, bestScore);
    for (UIView *child in view.subviews) CEFindAccessibilityTitleRecursive(child, screenPoint, depth + 1, bestTitle, bestScore);
}

static NSString *CEAccessibilityConversationTitleAtPoint(UIWindow *window, CGPoint point) {
    if (!window) return nil;
    CGPoint screenPoint = [window convertPoint:point toWindow:nil];
    NSString *bestTitle = nil; CGFloat bestScore = -CGFLOAT_MAX;
    CEFindAccessibilityTitleRecursive(window, screenPoint, 0, &bestTitle, &bestScore);
    return bestTitle;
}

static void CECollectTopLabels(UIView *view, UIWindow *window, NSUInteger depth, NSMutableArray<UILabel *> *out) {
    if (!view || depth > 12 || view.hidden || view.alpha < 0.02) return;
    if ([view isKindOfClass:UILabel.class]) {
        CGRect frame = [view convertRect:view.bounds toView:window];
        if (CGRectGetMinY(frame) >= window.safeAreaInsets.top - 8 && CGRectGetMaxY(frame) <= window.safeAreaInsets.top + 150) [out addObject:(UILabel *)view];
    }
    for (UIView *child in view.subviews) CECollectTopLabels(child, window, depth + 1, out);
}

static NSString *CETrimmedLabelText(UILabel *label) { return [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

static UILabel *CEProjectConversationTitleLabel(UIWindow *window) {
    if (!window) return nil;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array]; CECollectTopLabels(window, window, 0, labels);
    UILabel *subtitle = nil; CGRect subtitleFrame = CGRectNull;
    for (UILabel *label in labels) {
        if (![CETrimmedLabelText(label) isEqualToString:@"聊天"]) continue;
        CGRect frame = [label convertRect:label.bounds toView:window];
        if (!subtitle || CGRectGetMinY(frame) < CGRectGetMinY(subtitleFrame)) { subtitle = label; subtitleFrame = frame; }
    }
    if (!subtitle) return nil;

    UILabel *best = nil; CGFloat bestScore = -CGFLOAT_MAX;
    for (UILabel *label in labels) {
        if (label == subtitle) continue;
        NSString *text = CETrimmedLabelText(label); if (text.length < 1 || text.length > 120 || [text containsString:@"\n"]) continue;
        CGRect frame = [label convertRect:label.bounds toView:window];
        CGFloat verticalGap = CGRectGetMinY(subtitleFrame) - CGRectGetMaxY(frame);
        if (verticalGap < -4 || verticalGap > 52) continue;
        CGFloat centerDelta = fabs(CGRectGetMidX(frame) - CGRectGetMidX(subtitleFrame));
        if (centerDelta > 70) continue;
        if (label.font.pointSize + 0.5 < subtitle.font.pointSize) continue;
        CGFloat score = label.font.pointSize * 4.0 - verticalGap - centerDelta * 0.15;
        if (score > bestScore) { best = label; bestScore = score; }
    }
    return best;
}

static void CERemoveProjectHeaderMarker(UILabel *label) { [[label viewWithTag:CEProjectHeaderMarkerTag] removeFromSuperview]; }

static void CEInstallProjectHeaderMarker(UILabel *label, NSString *title) {
    if (!label || !title.length) return;
    [label.superview layoutIfNeeded];
    UIImageView *marker = (UIImageView *)[label viewWithTag:CEProjectHeaderMarkerTag];
    if (![marker isKindOfClass:UIImageView.class]) {
        marker = [UIImageView new]; marker.tag = CEProjectHeaderMarkerTag; marker.contentMode = UIViewContentModeScaleAspectFit; marker.isAccessibilityElement = NO; [label addSubview:marker];
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:8 weight:UIImageSymbolWeightRegular];
    marker.image = [[UIImage systemImageNamed:@"gearshape.fill"] imageWithConfiguration:config]; marker.tintColor = label.textColor ?: UIColor.labelColor;
    UIFont *font = label.font ?: [UIFont systemFontOfSize:17]; CGFloat textWidth = ceil([title sizeWithAttributes:@{NSFontAttributeName: font}].width);
    CGFloat textStart = 0;
    if (label.textAlignment == NSTextAlignmentCenter) textStart = MAX(0, (CGRectGetWidth(label.bounds) - textWidth) * 0.5);
    else if (label.textAlignment == NSTextAlignmentRight) textStart = MAX(0, CGRectGetWidth(label.bounds) - textWidth);
    CGFloat size = 8; marker.frame = CGRectMake(floor(textStart - size - 3), floor((CGRectGetHeight(label.bounds) - size) * 0.5 + 0.5), size, size);
}

static NSString *CEBestVisibleConversationTitle(void) {
    UIWindow *window = CEKeyWindow(); if (!window) return nil;
    NSArray<NSString *> *strings = CECollectVisibleStrings(window, 5);
    for (NSString *text in strings) {
        NSString *title = CEQuotedConversationTitle(text);
        if (title.length && [[CECatalog shared] recordsMatchingTitle:title].count) return title;
    }

    NSMutableArray<UILabel *> *labels = [NSMutableArray array]; CECollectTopLabels(window, window, 0, labels);
    UILabel *best = nil; CGFloat bestScore = -CGFLOAT_MAX;
    for (UILabel *label in labels) {
        if ([label viewWithTag:CEProjectHeaderMarkerTag]) continue;
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length < 2 || text.length > 120 || [text containsString:@"\n"] || ![[CECatalog shared] recordsMatchingTitle:text].count) continue;
        NSString *lower = text.lowercaseString;
        if ([lower isEqualToString:@"chatgpt"] || [text isEqualToString:@"聊天"] || [text isEqualToString:@"新聊天"]) continue;
        CGRect frame = [label convertRect:label.bounds toView:window];
        CGFloat centerPenalty = fabs(CGRectGetMidX(frame) - CGRectGetMidX(window.bounds)) * 0.04;
        CGFloat score = label.font.pointSize * 2.0 - centerPenalty + MIN((CGFloat)text.length, 30.0) * 0.15;
        if (score > bestScore) { best = label; bestScore = score; }
    }
    return [best.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray<CEConversationRecord *> *CECandidatesForSourceView(UIView *sourceView, NSString *identifierText, NSString *titleHint) {
    NSString *cid = CEExtractConversationIDFromString(identifierText ?: @"");
    if (cid.length) {
        CEConversationRecord *record = [[CECatalog shared] recordForID:cid];
        if (record) return @[record];
        CEConversationRecord *fallback = [CEConversationRecord new]; fallback.conversationID = cid; fallback.title = titleHint ?: CEBestTitleFromView(sourceView) ?: @"当前会话"; return @[fallback];
    }
    if (titleHint.length) {
        NSArray<CEConversationRecord *> *matches = [[CECatalog shared] recordsMatchingTitle:titleHint];
        if (matches.count) return matches;
    }
    UIView *view = sourceView ?: CELastTouchedView;
    return view ? [[CECatalog shared] candidatesForView:view] : @[];
}

static NSArray<UIMenuElement *> *CEAugmentedChildrenForSource(NSArray<UIMenuElement *> *children, UIView *sourceView, NSString *identifierText, NSString *titleHint) {
    if (CEMenuBuildGuard || CEHasExtensionSection(children) || !CELooksLikeConversationMenu(children)) return children;
    if (!sourceView && (!CELastTouchedView || !CELastTouchDate || [[NSDate date] timeIntervalSinceDate:CELastTouchDate] > 20.0)) return children;

    __weak UIView *weakSource = sourceView ?: CELastTouchedView;
    NSString *capturedIdentifier = [identifierText copy];
    NSString *capturedTitle = titleHint.length ? [titleHint copy] : ((CELastTouchDate && [[NSDate date] timeIntervalSinceDate:CELastTouchDate] <= 20.0) ? [CELastTouchedTitle copy] : nil);
    UIAction *rename = [UIAction actionWithTitle:@"重命名会话" image:[UIImage systemImageNamed:@"square.and.pencil"] identifier:@"com.whiteshark.chatgptenhancer.rename" handler:^(__unused UIAction *action) {
        [CEFeatures renameCandidates:CECandidatesForSourceView(weakSource, capturedIdentifier, capturedTitle) sourceView:weakSource];
    }];
    UIAction *exportMD = [UIAction actionWithTitle:@"导出 Markdown" image:[UIImage systemImageNamed:@"doc.text"] identifier:@"com.whiteshark.chatgptenhancer.export" handler:^(__unused UIAction *action) {
        [CEFeatures exportCandidates:CECandidatesForSourceView(weakSource, capturedIdentifier, capturedTitle) fromContextMenu:YES];
    }];

    CEMenuBuildGuard = YES;
    UIMenu *section = [UIMenu menuWithTitle:@"" image:nil identifier:CEExtensionMenuIdentifier options:UIMenuOptionsDisplayInline children:@[rename, exportMD]];
    CEMenuBuildGuard = NO;
    return [children arrayByAddingObject:section];
}

static NSArray<UIMenuElement *> *CEAugmentedChildren(NSArray<UIMenuElement *> *children) { return CEAugmentedChildrenForSource(children, CELastTouchedView, nil, nil); }

static void CEResolveConversationFromView(UIView *view) {
    if (!view) return;
    if (CELastTouchedTitle.length) {
        NSArray<CEConversationRecord *> *titleMatches = [[CECatalog shared] recordsMatchingTitle:CELastTouchedTitle];
        if (titleMatches.count == 1) {
            CEConversationRecord *record = titleMatches.firstObject;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [[CEConversationContext shared] setConversationID:record.conversationID title:record.title]; });
            return;
        }
    }
    NSArray<CEConversationRecord *> *candidates = [[CECatalog shared] candidatesForView:view];
    if (candidates.count != 1) return;
    CEConversationRecord *record = candidates.firstObject;
    if (!record.conversationID.length) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [[CEConversationContext shared] setConversationID:record.conversationID title:record.title]; });
}

@implementation UIWindow (ChatGPTEnhancerTouch)
- (void)ce_sendEvent:(UIEvent *)event {
    NSSet<UITouch *> *touches = event.allTouches;
    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CGPoint point = [touch locationInView:self];
        UIView *hit = [self hitTest:point withEvent:event];
        if (hit) {
            CELastTouchedView = hit; CELastTouchDate = [NSDate date];
            CELastTouchedTitle = CEAccessibilityConversationTitleAtPoint(self, point);
            CEResolveConversationFromView(hit);
        }
        if ([CEConversationContext shared].conversationID.length && point.x < 28) {
            NSDate *token = [NSDate date];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (CELastTouchDate && [CELastTouchDate compare:token] != NSOrderedAscending) return;
                [[CEConversationContext shared] clear];
            });
        }
    }
    [self ce_sendEvent:event];
}
@end

@implementation UIMenu (ChatGPTEnhancerMenu)
+ (instancetype)ce_menuWithTitle:(NSString *)title children:(NSArray<UIMenuElement *> *)children {
    if (CEMenuBuildGuard) return [self ce_menuWithTitle:title children:children];
    return [self ce_menuWithTitle:title children:CEAugmentedChildren(children)];
}
+ (instancetype)ce_menuWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children {
    if (CEMenuBuildGuard) return [self ce_menuWithTitle:title image:image identifier:identifier options:options children:children];
    if ([identifier isEqualToString:CEExtensionMenuIdentifier]) return [self ce_menuWithTitle:title image:image identifier:identifier options:options children:children];
    return [self ce_menuWithTitle:title image:image identifier:identifier options:options children:CEAugmentedChildren(children)];
}
+ (instancetype)ce_menuWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children API_AVAILABLE(ios(15.0)) {
    if (CEMenuBuildGuard) return [self ce_menuWithTitle:title subtitle:subtitle image:image identifier:identifier options:options children:children];
    if ([identifier isEqualToString:CEExtensionMenuIdentifier]) return [self ce_menuWithTitle:title subtitle:subtitle image:image identifier:identifier options:options children:children];
    return [self ce_menuWithTitle:title subtitle:subtitle image:image identifier:identifier options:options children:CEAugmentedChildren(children)];
}
- (UIMenu *)ce_menuByReplacingChildren:(NSArray<UIMenuElement *> *)children {
    if (CEMenuBuildGuard || [self.identifier isEqualToString:CEExtensionMenuIdentifier]) return [self ce_menuByReplacingChildren:children];
    NSArray<UIMenuElement *> *augmented = CEAugmentedChildrenForSource(children, CELastTouchedView, nil, nil);
    return [self ce_menuByReplacingChildren:augmented];
}
@end

@implementation UIContextMenuConfiguration (ChatGPTEnhancerContextMenu)
+ (instancetype)ce_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider {
    __weak UIView *sourceView = CELastTouchedView;
    NSString *identifierText = [(id)identifier description];
    NSString *titleHint = [CELastTouchedTitle copy];
    UIContextMenuActionProvider wrappedProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *menu = actionProvider ? actionProvider(suggestedActions) : [UIMenu menuWithTitle:@"" children:suggestedActions];
        if (!menu) return nil;
        NSArray<UIMenuElement *> *children = CEAugmentedChildrenForSource(menu.children, sourceView, identifierText, titleHint);
        CEMenuBuildGuard = YES;
        UIMenu *result = [menu menuByReplacingChildren:children];
        CEMenuBuildGuard = NO;
        return result;
    };
    return [self ce_configurationWithIdentifier:identifier previewProvider:previewProvider actionProvider:wrappedProvider];
}
@end

@interface CEProjectConversationHeaderController : NSObject
@property (nonatomic, weak) UILabel *modifiedLabel;
@property (nonatomic, copy) NSString *originalTitle;
@property (nonatomic, copy) NSString *appliedTitle;
@property (nonatomic, copy) NSString *conversationID;
@end

@implementation CEProjectConversationHeaderController
+ (instancetype)shared { static CEProjectConversationHeaderController *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEProjectConversationHeaderController new]; }); return v; }
- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:CEConversationContextDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:CECatalogDidChangeNotification object:nil];
    [self refresh:nil];
}
- (void)restoreCurrentModification {
    UILabel *label = self.modifiedLabel;
    if (label) {
        CERemoveProjectHeaderMarker(label);
        NSString *current = CETrimmedLabelText(label);
        if (self.appliedTitle.length && self.originalTitle.length && [current isEqualToString:self.appliedTitle]) label.text = self.originalTitle;
    }
    self.modifiedLabel = nil; self.originalTitle = nil; self.appliedTitle = nil; self.conversationID = nil;
}
- (NSString *)currentConversationTitle {
    NSString *cid = [CEConversationContext shared].conversationID; if (!cid.length) return nil;
    CEConversationRecord *record = [[CECatalog shared] recordForID:cid];
    NSString *title = record.title.length ? record.title : [CEConversationContext shared].title;
    title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length || [title isEqualToString:@"当前会话"] || [title isEqualToString:@"ChatGPT Conversation"]) return nil;
    return title;
}
- (void)refresh:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = CEKeyWindow(); NSString *cid = [CEConversationContext shared].conversationID; NSString *title = [self currentConversationTitle];
        UILabel *target = window ? CEProjectConversationTitleLabel(window) : nil;
        if (!cid.length || !title.length || !target) { [self restoreCurrentModification]; return; }
        if (self.modifiedLabel && self.modifiedLabel != target) [self restoreCurrentModification];

        NSString *current = CETrimmedLabelText(target);
        if (target == self.modifiedLabel) {
            if (![current isEqualToString:title]) target.text = title;
            if ([CETrimmedLabelText(target) isEqualToString:title]) { self.appliedTitle = title; self.conversationID = cid; CEInstallProjectHeaderMarker(target, title); }
            return;
        }
        if ([current isEqualToString:title]) { CERemoveProjectHeaderMarker(target); return; }
        if (!current.length) return;

        self.modifiedLabel = target; self.originalTitle = current; self.appliedTitle = title; self.conversationID = cid;
        target.text = title;
        if ([CETrimmedLabelText(target) isEqualToString:title]) CEInstallProjectHeaderMarker(target, title);
        else [self restoreCurrentModification];
    });
}
@end

@interface CEFloatingButtonController : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) CGFloat keyboardTop;
@end

@implementation CEFloatingButtonController
+ (instancetype)shared { static CEFloatingButtonController *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEFloatingButtonController new]; }); return v; }
- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextChanged:) name:CEConversationContextDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextChanged:) name:CECatalogDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    [self contextChanged:nil];
}
- (UIButton *)button {
    if (_button) return _button;
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    _button.frame = CGRectMake(0, 0, 48, 44); _button.layer.cornerRadius = 14; _button.layer.masksToBounds = NO;
    _button.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.96];
    UIImageSymbolConfiguration *gearConfig = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
    [_button setImage:[[UIImage systemImageNamed:@"gearshape.fill"] imageWithConfiguration:gearConfig] forState:UIControlStateNormal];
    _button.accessibilityLabel = @"ChatGPTEnhancer 会话工具";
    _button.layer.shadowColor = UIColor.blackColor.CGColor; _button.layer.shadowOpacity = 0.16; _button.layer.shadowRadius = 8; _button.layer.shadowOffset = CGSizeMake(0, 3);
    [_button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]; [_button addGestureRecognizer:pan];
    return _button;
}
- (void)contextChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = CEKeyWindow(); if (!window) return; self.window = window;
        if (self.button.superview != window) { [self.button removeFromSuperview]; [window addSubview:self.button]; }
        CGFloat savedY = [[NSUserDefaults standardUserDefaults] doubleForKey:@"ChatGPTEnhancer.FloatingY"];
        if (savedY <= 0.05 || savedY >= 0.95) savedY = 0.42;
        CGFloat x = MAX(8, window.bounds.size.width - self.button.bounds.size.width - 10);
        CGFloat usableBottom = self.keyboardTop > 0 ? MIN(window.bounds.size.height - 12, self.keyboardTop - 12) : window.bounds.size.height - window.safeAreaInsets.bottom - 18;
        CGFloat y = MAX(window.safeAreaInsets.top + 24, MIN(usableBottom - self.button.bounds.size.height, window.bounds.size.height * savedY));
        self.button.frame = CGRectMake(x, y, self.button.bounds.size.width, self.button.bounds.size.height);
    });
}
- (CEConversationRecord *)currentRecord {
    NSString *visibleTitle = CEBestVisibleConversationTitle();
    if (visibleTitle.length) {
        NSArray<CEConversationRecord *> *matches = [[CECatalog shared] recordsMatchingTitle:visibleTitle];
        if (matches.count == 1) {
            CEConversationRecord *visibleRecord = matches.firstObject;
            if (visibleRecord.conversationID.length) {
                [[CEConversationContext shared] setConversationID:visibleRecord.conversationID title:visibleRecord.title];
                return visibleRecord;
            }
        }
    }
    NSString *cid = CERefreshVisibleConversationContext(); if (!cid.length) return nil;
    CEConversationRecord *record = [[CECatalog shared] recordForID:cid] ?: [CEConversationRecord new];
    if (!record.conversationID.length) record.conversationID = cid;
    if (!record.title.length || [record.title isEqualToString:@"当前会话"]) record.title = [CEConversationContext shared].title ?: @"ChatGPT Conversation";
    return record;
}
- (BOOL)verifyRecordStillVisible:(CEConversationRecord *)record {
    NSString *visibleID = CERefreshVisibleConversationContext();
    if (!visibleID.length || ![visibleID isEqualToString:record.conversationID]) { CEShowMessage(@"无法确认当前可见会话，已取消操作。"); return NO; }
    return YES;
}
- (void)buttonTapped {
    CEConversationRecord *record = [self currentRecord];
    if (!record.conversationID.length) { CEShowMessage(@"无法确认当前可见会话，已停止操作。"); return; }
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"会话工具" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"拉取最新消息" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { if ([self verifyRecordStillVisible:record]) [CEFeatures pullLatestCurrentConversation]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"采集重载诊断（不跳页）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { if ([self verifyRecordStillVisible:record]) [CEFeatures reloadCurrentConversation]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出 MD 文档" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { if ([self verifyRecordStillVisible:record]) [CEFeatures exportRecord:record requireConfirmation:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制完整诊断" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        CERecoveryDiagnosticMark(@"USER COPIED FULL DIAGNOSTICS");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CECopyDiagnostics(self.button, nil); });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.button; sheet.popoverPresentationController.sourceRect = self.button.bounds;
    [vc presentViewController:sheet animated:YES completion:nil];
}
- (void)pan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view; UIWindow *window = self.window; if (!view || !window) return;
    CGPoint translation = [pan translationInView:window]; CGPoint center = view.center; center.y += translation.y; [pan setTranslation:CGPointZero inView:window];
    CGFloat minY = window.safeAreaInsets.top + view.bounds.size.height / 2 + 12;
    CGFloat maxY = window.bounds.size.height - window.safeAreaInsets.bottom - view.bounds.size.height / 2 - 18;
    if (self.keyboardTop > 0) maxY = MIN(maxY, self.keyboardTop - view.bounds.size.height / 2 - 12);
    center.y = MAX(minY, MIN(maxY, center.y)); center.x = window.bounds.size.width - view.bounds.size.width / 2 - 10; view.center = center;
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [[NSUserDefaults standardUserDefaults] setDouble:(center.y / MAX(window.bounds.size.height, 1)) forKey:@"ChatGPTEnhancer.FloatingY"];
}
- (void)keyboardChanged:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue]; UIWindow *window = self.window ?: CEKeyWindow();
    self.keyboardTop = window ? [window convertRect:frame fromWindow:nil].origin.y : 0; [self contextChanged:nil];
}
- (void)keyboardHidden:(NSNotification *)note { self.keyboardTop = 0; [self contextChanged:nil]; }
@end

@implementation CEEnhancerUI
+ (instancetype)shared { static CEEnhancerUI *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEEnhancerUI new]; }); return v; }
- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(ce_sendEvent:));
        CESwizzleClassMethod(UIMenu.class, @selector(menuWithTitle:children:), @selector(ce_menuWithTitle:children:));
        CESwizzleClassMethod(UIMenu.class, @selector(menuWithTitle:image:identifier:options:children:), @selector(ce_menuWithTitle:image:identifier:options:children:));
        SEL modern = @selector(menuWithTitle:subtitle:image:identifier:options:children:);
        if ([UIMenu respondsToSelector:modern]) CESwizzleClassMethod(UIMenu.class, modern, @selector(ce_menuWithTitle:subtitle:image:identifier:options:children:));
        if ([UIMenu instancesRespondToSelector:@selector(menuByReplacingChildren:)]) CESwizzleInstanceMethod(UIMenu.class, @selector(menuByReplacingChildren:), @selector(ce_menuByReplacingChildren:));
        SEL contextFactory = @selector(configurationWithIdentifier:previewProvider:actionProvider:);
        if ([UIContextMenuConfiguration respondsToSelector:contextFactory]) CESwizzleClassMethod(UIContextMenuConfiguration.class, contextFactory, @selector(ce_configurationWithIdentifier:previewProvider:actionProvider:));
        [[CEProjectConversationHeaderController shared] start];
        [[CEFloatingButtonController shared] start];
    });
}
@end
