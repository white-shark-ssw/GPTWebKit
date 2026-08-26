#import "CEEnhancerUI.h"
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"
#import "../Diagnostics/CEConversationIdentityTrace.h"
#import <objc/runtime.h>

static __weak UIView *CELastTouchedView = nil;
static NSDate *CELastTouchDate = nil;
static CGPoint CELastTouchPoint = {0, 0};
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
        if (![element isKindOfClass:UIMenu.class]) continue;
        UIMenu *menu = (UIMenu *)element;
        if ([menu.identifier isEqualToString:CEExtensionMenuIdentifier] || CEHasExtensionSection(menu.children)) return YES;
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

static UIView *CERecentMenuSource(UIView *sourceView) {
    if (sourceView) return sourceView;
    if (!CELastTouchedView || !CELastTouchDate || [[NSDate date] timeIntervalSinceDate:CELastTouchDate] > 2.0) return nil;
    return CELastTouchedView;
}

static BOOL CEIsCurrentConversationHeaderSource(UIView *sourceView) {
    UIView *view = CERecentMenuSource(sourceView); UIWindow *window = view.window ?: CEKeyWindow(); if (!view || !window) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGFloat headerTop = MAX(0.0, window.safeAreaInsets.top - 20.0); CGFloat headerBottom = MAX(120.0, window.safeAreaInsets.top + 84.0);
    if (!CGRectIsEmpty(frame) && CGRectGetMidY(frame) >= headerTop && CGRectGetMidY(frame) <= headerBottom) return YES;
    if (!CELastTouchDate || [[NSDate date] timeIntervalSinceDate:CELastTouchDate] > 2.0) return NO;
    return CELastTouchPoint.y >= headerTop && CELastTouchPoint.y <= headerBottom;
}

static NSString *CETraceSafeStructuralText(NSString *value) {
    if (!value.length) return @"<none>";
    if (value.length > 180) return [NSString stringWithFormat:@"<redacted len=%lu>", (unsigned long)value.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:/"];
    if ([value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) return value;
    return [NSString stringWithFormat:@"<redacted len=%lu>", (unsigned long)value.length];
}

static void CETraceMenuElements(NSArray<UIMenuElement *> *elements, NSString *prefix, NSUInteger depth) {
    if (!CEConversationIdentityTraceIsRecording() || depth > 8) return;
    NSUInteger index = 0;
    for (UIMenuElement *element in elements) {
        NSString *path = [NSString stringWithFormat:@"%@%lu", prefix ?: @"", (unsigned long)index++];
        if ([element isKindOfClass:UIAction.class]) {
            UIAction *action = (UIAction *)element;
            CEConversationIdentityTraceLog(@"MENU-ELEMENT", @"path=%@ type=action title=%@ identifier=%@ attributes=%lu state=%ld", path, action.title ?: @"", CETraceSafeStructuralText(action.identifier), (unsigned long)action.attributes, (long)action.state);
        } else if ([element isKindOfClass:UIMenu.class]) {
            UIMenu *menu = (UIMenu *)element;
            CEConversationIdentityTraceLog(@"MENU-ELEMENT", @"path=%@ type=menu title=%@ identifier=%@ options=%lu children=%lu", path, menu.title ?: @"", CETraceSafeStructuralText(menu.identifier), (unsigned long)menu.options, (unsigned long)menu.children.count);
            CETraceMenuElements(menu.children, [path stringByAppendingString:@"."], depth + 1);
        } else CEConversationIdentityTraceLog(@"MENU-ELEMENT", @"path=%@ type=%@", path, NSStringFromClass(element.class));
    }
}

static void CETraceMenuSource(UIView *sourceView) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    UIView *view = CERecentMenuSource(sourceView); UIWindow *window = view.window ?: CEKeyWindow();
    if (!view || !window) { CEConversationIdentityTraceLog(@"MENU-SOURCE", @"source=<nil> lastTouch={%.1f,%.1f}", CELastTouchPoint.x, CELastTouchPoint.y); return; }
    CGRect frame = [view convertRect:view.bounds toView:window];
    CEConversationIdentityTraceLog(@"MENU-SOURCE", @"class=%@ frame=%@ accessibilityIdentifier=%@ lastTouch={%.1f,%.1f} currentHeader=%@", NSStringFromClass(view.class), NSStringFromCGRect(frame), CETraceSafeStructuralText(view.accessibilityIdentifier), CELastTouchPoint.x, CELastTouchPoint.y, CEIsCurrentConversationHeaderSource(view) ? @"YES" : @"NO");
}

static BOOL CEMenuTitleConflictsWithTarget(NSString *menuTitle, NSString *targetTitle) {
    NSString *menu = [menuTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSString *target = [targetTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!menu.length || !target.length || [menu isEqualToString:target]) return NO;
    return [[CECatalog shared] recordsMatchingTitle:menu].count > 0;
}

static NSString *CEUsableMenuPresentationTitle(NSString *menuTitle) {
    NSString *title = [menuTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length || title.length > 160 || [title containsString:@"\n"] || [title isEqualToString:@"聊天"] || [title isEqualToString:@"新聊天"] || [title.lowercaseString isEqualToString:@"chatgpt"]) return nil;
    return title;
}

static void CETraceConversationMenu(NSArray<UIMenuElement *> *children, UIView *sourceView, NSString *origin, NSString *identifierText, NSString *identifierClass, NSString *menuTitle, NSString *targetID, NSString *targetTitle) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    CEConversationContext *context = [CEConversationContext shared];
    CEConversationIdentityTraceLog(@"MENU", @"origin=%@ configIdentifierClass=%@ configIdentifier=%@ menuTitle=%@ contextID=%@ contextTitle=%@ capturedTargetID=%@ capturedTitle=%@", origin ?: @"unknown", identifierClass ?: @"<none>", CETraceSafeStructuralText(identifierText), menuTitle ?: @"<none>", context.conversationID ?: @"<none>", context.title ?: @"<none>", targetID ?: @"<none>", targetTitle ?: @"<none>");
    CETraceMenuSource(sourceView); CETraceMenuElements(children, @"", 0);
}

static void CEPresentIdentityTraceFile(NSURL *url) {
    if (!url) { CEShowMessage(@"识别日志文件不可用。"); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = CETopViewController(); if (!vc) return;
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES]; picker.shouldShowFileExtensions = YES; [vc presentViewController:picker animated:YES completion:nil];
    });
}

static NSArray<UIMenuElement *> *CEAugmentedChildrenForSource(NSArray<UIMenuElement *> *children, UIView *sourceView, NSString *origin, NSString *identifierText, NSString *identifierClass, NSString *menuTitle) {
    if (CEMenuBuildGuard || CEHasExtensionSection(children) || !CELooksLikeConversationMenu(children)) return children;
    UIView *resolvedSource = CERecentMenuSource(sourceView);
    if (!CEIsCurrentConversationHeaderSource(resolvedSource)) {
        if (CEConversationIdentityTraceIsRecording()) { CEConversationIdentityTraceLog(@"MENU-SKIP", @"origin=%@ reason=not-current-header", origin ?: @"unknown"); CETraceMenuSource(resolvedSource); }
        return children;
    }

    CEConversationContext *context = [CEConversationContext shared]; NSString *targetID = [context.conversationID copy]; CEConversationRecord *catalog = targetID.length ? [[CECatalog shared] recordForID:targetID] : nil;
    NSString *targetTitle = [(catalog.title.length ? catalog.title : context.title) copy];
    if (CEMenuTitleConflictsWithTarget(menuTitle, targetTitle)) {
        CEConversationIdentityTraceLog(@"MENU-SKIP", @"origin=%@ reason=title-conflict menuTitle=%@ targetID=%@ targetTitle=%@", origin ?: @"unknown", menuTitle ?: @"<none>", targetID ?: @"<none>", targetTitle ?: @"<none>"); return children;
    }
    NSString *presentationTitle = CEUsableMenuPresentationTitle(menuTitle);
    if (targetID.length && presentationTitle.length) { [[CECatalog shared] updateTitle:presentationTitle forConversationID:targetID]; targetTitle = presentationTitle; CEConversationIdentityTraceLog(@"HEADER-TITLE", @"menu-presentation target=%@ title=%@", targetID, presentationTitle); }
    CETraceConversationMenu(children, resolvedSource, origin, identifierText, identifierClass, menuTitle, targetID, targetTitle);

    NSMutableArray<UIMenuElement *> *enhancerActions = [NSMutableArray array];
    if (targetID.length) {
        NSString *capturedID = [targetID copy]; NSString *capturedTitle = [targetTitle copy];
        [enhancerActions addObject:[UIAction actionWithTitle:@"拉取最新消息" image:[UIImage systemImageNamed:@"arrow.down.circle"] identifier:@"com.whiteshark.chatgptenhancer.pull" handler:^(__unused UIAction *action) { [CEFeatures pullLatestConversationID:capturedID]; }]];
        [enhancerActions addObject:[UIAction actionWithTitle:@"重载当前会话" image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:@"com.whiteshark.chatgptenhancer.reload" handler:^(__unused UIAction *action) { [CEFeatures reloadConversationID:capturedID]; }]];
        [enhancerActions addObject:[UIAction actionWithTitle:@"重命名会话" image:[UIImage systemImageNamed:@"square.and.pencil"] identifier:@"com.whiteshark.chatgptenhancer.rename" handler:^(__unused UIAction *action) { [CEFeatures renameConversationID:capturedID title:capturedTitle]; }]];
        [enhancerActions addObject:[UIAction actionWithTitle:@"导出 Markdown" image:[UIImage systemImageNamed:@"doc.text"] identifier:@"com.whiteshark.chatgptenhancer.export" handler:^(__unused UIAction *action) { [CEFeatures exportConversationID:capturedID title:capturedTitle]; }]];
    } else {
        UIAction *unavailable = [UIAction actionWithTitle:@"会话识别未就绪" image:[UIImage systemImageNamed:@"exclamationmark.circle"] identifier:@"com.whiteshark.chatgptenhancer.unavailable" handler:^(__unused UIAction *action) { CEShowMessage(@"尚未收到当前会话的精确识别信息。"); }];
        unavailable.attributes = UIMenuElementAttributesDisabled; [enhancerActions addObject:unavailable];
    }

    BOOL traceRecording = CEConversationIdentityTraceIsRecording(); NSString *capturedOrigin = [origin copy]; NSString *capturedTraceTarget = [targetID copy];
    [enhancerActions addObject:[UIAction actionWithTitle:(traceRecording ? @"结束并导出识别日志" : @"开始会话识别记录") image:[UIImage systemImageNamed:(traceRecording ? @"square.and.arrow.up" : @"record.circle")] identifier:@"com.whiteshark.chatgptenhancer.identity-trace" handler:^(__unused UIAction *action) {
        if (traceRecording) { CEConversationIdentityTraceLog(@"USER", @"finish identity trace from menu origin=%@", capturedOrigin ?: @"unknown"); CEPresentIdentityTraceFile(CEConversationIdentityTraceFinish()); }
        else { CEConversationIdentityTraceBegin(); CEConversationIdentityTraceLog(@"USER", @"begin identity trace from menu origin=%@ target=%@", capturedOrigin ?: @"unknown", capturedTraceTarget ?: @"<none>"); CEShowMessage(@"会话识别记录已开始；关闭并重新打开 ChatGPT 后仍会继续记录。"); }
    }]];

    CEMenuBuildGuard = YES; UIMenu *section = [UIMenu menuWithTitle:@"" image:nil identifier:CEExtensionMenuIdentifier options:UIMenuOptionsDisplayInline children:enhancerActions]; CEMenuBuildGuard = NO;
    return [children arrayByAddingObject:section];
}

static NSArray<UIMenuElement *> *CEAugmentedChildren(NSString *title, NSArray<UIMenuElement *> *children) { return CEAugmentedChildrenForSource(children, nil, @"menu-factory", nil, nil, title); }

@implementation UIWindow (ChatGPTEnhancerTouch)
- (void)ce_sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CELastTouchPoint = [touch locationInView:self]; CELastTouchedView = [self hitTest:CELastTouchPoint withEvent:event]; CELastTouchDate = [NSDate date];
    }
    [self ce_sendEvent:event];
}
@end

@implementation UIMenu (ChatGPTEnhancerMenu)
+ (instancetype)ce_menuWithTitle:(NSString *)title children:(NSArray<UIMenuElement *> *)children {
    if (CEMenuBuildGuard) return [self ce_menuWithTitle:title children:children];
    return [self ce_menuWithTitle:title children:CEAugmentedChildren(title, children)];
}
+ (instancetype)ce_menuWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children {
    if (CEMenuBuildGuard) return [self ce_menuWithTitle:title image:image identifier:identifier options:options children:children];
    if ([identifier isEqualToString:CEExtensionMenuIdentifier]) return [self ce_menuWithTitle:title image:image identifier:identifier options:options children:children];
    NSArray<UIMenuElement *> *augmented = CEAugmentedChildrenForSource(children, nil, @"menu-factory-identifier", [identifier description], identifier ? NSStringFromClass([(id)identifier class]) : nil, title);
    return [self ce_menuWithTitle:title image:image identifier:identifier options:options children:augmented];
}
+ (instancetype)ce_menuWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children API_AVAILABLE(ios(15.0)) {
    if (CEMenuBuildGuard) return [self ce_menuWithTitle:title subtitle:subtitle image:image identifier:identifier options:options children:children];
    if ([identifier isEqualToString:CEExtensionMenuIdentifier]) return [self ce_menuWithTitle:title subtitle:subtitle image:image identifier:identifier options:options children:children];
    NSArray<UIMenuElement *> *augmented = CEAugmentedChildrenForSource(children, nil, @"menu-factory-modern", [identifier description], identifier ? NSStringFromClass([(id)identifier class]) : nil, title);
    return [self ce_menuWithTitle:title subtitle:subtitle image:image identifier:identifier options:options children:augmented];
}
- (UIMenu *)ce_menuByReplacingChildren:(NSArray<UIMenuElement *> *)children {
    if (CEMenuBuildGuard || [self.identifier isEqualToString:CEExtensionMenuIdentifier]) return [self ce_menuByReplacingChildren:children];
    NSArray<UIMenuElement *> *augmented = CEAugmentedChildrenForSource(children, nil, @"menu-replace", [self.identifier description], self.identifier ? NSStringFromClass([(id)self.identifier class]) : nil, self.title);
    return [self ce_menuByReplacingChildren:augmented];
}
@end

@implementation UIContextMenuConfiguration (ChatGPTEnhancerContextMenu)
+ (instancetype)ce_configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider actionProvider:(UIContextMenuActionProvider)actionProvider {
    __weak UIView *sourceView = CERecentMenuSource(nil); NSString *identifierText = [(id)identifier description]; NSString *identifierClass = identifier ? NSStringFromClass([(id)identifier class]) : nil;
    UIContextMenuActionProvider wrappedProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *menu = actionProvider ? actionProvider(suggestedActions) : [UIMenu menuWithTitle:@"" children:suggestedActions]; if (!menu) return nil;
        NSArray<UIMenuElement *> *children = CEAugmentedChildrenForSource(menu.children, sourceView, @"context-menu-config", identifierText, identifierClass, menu.title);
        CEMenuBuildGuard = YES; UIMenu *result = [menu menuByReplacingChildren:children]; CEMenuBuildGuard = NO; return result;
    };
    return [self ce_configurationWithIdentifier:identifier previewProvider:previewProvider actionProvider:wrappedProvider];
}
@end

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
        CGRect frame = [label convertRect:label.bounds toView:window]; CGFloat verticalGap = CGRectGetMinY(subtitleFrame) - CGRectGetMaxY(frame); if (verticalGap < -4 || verticalGap > 52) continue;
        CGFloat centerDelta = fabs(CGRectGetMidX(frame) - CGRectGetMidX(subtitleFrame)); if (centerDelta > 70 || label.font.pointSize + 0.5 < subtitle.font.pointSize) continue;
        CGFloat score = label.font.pointSize * 4.0 - verticalGap - centerDelta * 0.15; if (score > bestScore) { best = label; bestScore = score; }
    }
    return best;
}

static void CETraceProjectHeaderWindows(void) {
    if (!CEConversationIdentityTraceIsRecording()) return;
    NSUInteger windowIndex = 0;
    for (UIWindow *window in CEForegroundWindows()) {
        NSMutableArray<UILabel *> *labels = [NSMutableArray array]; CECollectTopLabels(window, window, 0, labels);
        CEConversationIdentityTraceLog(@"HEADER-WINDOW", @"window[%lu] class=%@ key=%@ level=%.1f frame=%@ topLabelCount=%lu", (unsigned long)windowIndex++, NSStringFromClass(window.class), window.isKeyWindow ? @"YES" : @"NO", window.windowLevel, NSStringFromCGRect(window.frame), (unsigned long)labels.count);
        NSUInteger labelIndex = 0;
        for (UILabel *label in labels) {
            NSString *text = CETrimmedLabelText(label); CGRect frame = [label convertRect:label.bounds toView:window];
            CEConversationIdentityTraceLog(@"HEADER-LABEL", @"label[%lu] class=%@ frame=%@ text=%@", (unsigned long)labelIndex++, NSStringFromClass(label.class), NSStringFromCGRect(frame), text.length ? text : @"<none>");
        }
    }
}

static UILabel *CEProjectConversationTitleTarget(void) {
    for (UIWindow *window in CEForegroundWindows()) {
        UILabel *label = CEProjectConversationTitleLabel(window);
        if (label) { CEConversationIdentityTraceLog(@"HEADER-TARGET", @"windowClass=%@ key=%@ title=%@", NSStringFromClass(window.class), window.isKeyWindow ? @"YES" : @"NO", CETrimmedLabelText(label)); return label; }
    }
    CETraceProjectHeaderWindows(); return nil;
}

static void CERemoveProjectHeaderMarker(UILabel *label) { [[label viewWithTag:CEProjectHeaderMarkerTag] removeFromSuperview]; }

static void CEInstallProjectHeaderMarker(UILabel *label, NSString *title) {
    if (!label || !title.length) return; [label.superview layoutIfNeeded];
    UIImageView *marker = (UIImageView *)[label viewWithTag:CEProjectHeaderMarkerTag];
    if (![marker isKindOfClass:UIImageView.class]) { marker = [UIImageView new]; marker.tag = CEProjectHeaderMarkerTag; marker.contentMode = UIViewContentModeScaleAspectFit; marker.isAccessibilityElement = NO; [label addSubview:marker]; }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:8 weight:UIImageSymbolWeightRegular]; marker.image = [[UIImage systemImageNamed:@"gearshape.fill"] imageWithConfiguration:config]; marker.tintColor = label.textColor ?: UIColor.labelColor;
    UIFont *font = label.font ?: [UIFont systemFontOfSize:17]; CGFloat textWidth = ceil([title sizeWithAttributes:@{NSFontAttributeName:font}].width); CGFloat textStart = 0;
    if (label.textAlignment == NSTextAlignmentCenter) textStart = MAX(0, (CGRectGetWidth(label.bounds) - textWidth) * 0.5); else if (label.textAlignment == NSTextAlignmentRight) textStart = MAX(0, CGRectGetWidth(label.bounds) - textWidth);
    CGFloat size = 8; marker.frame = CGRectMake(floor(textStart - size - 3), floor((CGRectGetHeight(label.bounds) - size) * 0.5 + 0.5), size, size);
}

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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:CECatalogDidChangeNotification object:nil]; [self refresh:nil];
}
- (void)restoreCurrentModification {
    UILabel *label = self.modifiedLabel;
    if (label) { CERemoveProjectHeaderMarker(label); NSString *current = CETrimmedLabelText(label); if (self.appliedTitle.length && self.originalTitle.length && [current isEqualToString:self.appliedTitle]) label.text = self.originalTitle; }
    self.modifiedLabel = nil; self.originalTitle = nil; self.appliedTitle = nil; self.conversationID = nil;
}
- (NSString *)currentConversationTitle {
    NSString *cid = [CEConversationContext shared].conversationID; if (!cid.length) return nil;
    CEConversationRecord *record = [[CECatalog shared] recordForID:cid]; NSString *title = record.title.length ? record.title : [CEConversationContext shared].title; title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length || [title isEqualToString:@"当前会话"] || [title isEqualToString:@"ChatGPT Conversation"]) return nil; return title;
}
- (void)refresh:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *cid = [CEConversationContext shared].conversationID; NSString *title = [self currentConversationTitle]; UILabel *target = CEProjectConversationTitleTarget();
        if (!cid.length || !title.length || !target) { [self restoreCurrentModification]; return; }
        if (self.modifiedLabel && self.modifiedLabel != target) [self restoreCurrentModification];
        NSString *current = CETrimmedLabelText(target);
        if (target == self.modifiedLabel) { if (![current isEqualToString:title]) target.text = title; if ([CETrimmedLabelText(target) isEqualToString:title]) { self.appliedTitle = title; self.conversationID = cid; CEInstallProjectHeaderMarker(target, title); } return; }
        if ([current isEqualToString:title]) { CEInstallProjectHeaderMarker(target, title); return; } if (!current.length) return;
        self.modifiedLabel = target; self.originalTitle = current; self.appliedTitle = title; self.conversationID = cid; target.text = title;
        if ([CETrimmedLabelText(target) isEqualToString:title]) CEInstallProjectHeaderMarker(target, title); else [self restoreCurrentModification];
    });
}
@end

@implementation CEEnhancerUI
+ (instancetype)shared { static CEEnhancerUI *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CEEnhancerUI new]; }); return v; }
- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CESwizzleInstanceMethod(UIWindow.class, @selector(sendEvent:), @selector(ce_sendEvent:));
        CESwizzleClassMethod(UIMenu.class, @selector(menuWithTitle:children:), @selector(ce_menuWithTitle:children:));
        CESwizzleClassMethod(UIMenu.class, @selector(menuWithTitle:image:identifier:options:children:), @selector(ce_menuWithTitle:image:identifier:options:children:));
        SEL modern = @selector(menuWithTitle:subtitle:image:identifier:options:children:); if ([UIMenu respondsToSelector:modern]) CESwizzleClassMethod(UIMenu.class, modern, @selector(ce_menuWithTitle:subtitle:image:identifier:options:children:));
        if ([UIMenu instancesRespondToSelector:@selector(menuByReplacingChildren:)]) CESwizzleInstanceMethod(UIMenu.class, @selector(menuByReplacingChildren:), @selector(ce_menuByReplacingChildren:));
        SEL contextFactory = @selector(configurationWithIdentifier:previewProvider:actionProvider:); if ([UIContextMenuConfiguration respondsToSelector:contextFactory]) CESwizzleClassMethod(UIContextMenuConfiguration.class, contextFactory, @selector(ce_configurationWithIdentifier:previewProvider:actionProvider:));
        [[CEProjectConversationHeaderController shared] start];
    });
}
@end