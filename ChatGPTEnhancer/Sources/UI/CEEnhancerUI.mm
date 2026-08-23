#import "CEEnhancerUI.h"
#import "../Core/CECore.h"
#import "../Storage/CECatalog.h"
#import "../Features/CEFeatures.h"
#import <objc/runtime.h>

static __weak UIView *CELastTouchedView = nil;
static NSDate *CELastTouchDate = nil;
static BOOL CEMenuBuildGuard = NO;
static NSString * const CEExtensionMenuIdentifier = @"com.whiteshark.chatgptenhancer.section";

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
        @[@"rename", @"重命名", @"重新命名"], @[@"archive", @"归档"], @[@"delete", @"删除"], @[@"move", @"移至", @"移动"], @[@"share", @"共享", @"分享"]
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

static NSArray<UIMenuElement *> *CEAugmentedChildren(NSArray<UIMenuElement *> *children) {
    if (CEMenuBuildGuard || CEHasExtensionSection(children) || !CELooksLikeConversationMenu(children)) return children;
    if (!CELastTouchedView || !CELastTouchDate || [[NSDate date] timeIntervalSinceDate:CELastTouchDate] > 3.0) return children;
    NSArray<CEConversationRecord *> *candidates = [[CECatalog shared] candidatesForView:CELastTouchedView];
    if (!candidates.count) return children;

    __weak UIView *sourceView = CELastTouchedView;
    UIAction *rename = [UIAction actionWithTitle:@"重命名会话" image:[UIImage systemImageNamed:@"square.and.pencil"] identifier:@"com.whiteshark.chatgptenhancer.rename" handler:^(__unused UIAction *action) {
        [CEFeatures renameCandidates:candidates sourceView:sourceView];
    }];
    UIAction *exportMD = [UIAction actionWithTitle:@"导出 Markdown" image:[UIImage systemImageNamed:@"doc.text"] identifier:@"com.whiteshark.chatgptenhancer.export" handler:^(__unused UIAction *action) {
        [CEFeatures exportCandidates:candidates fromContextMenu:YES];
    }];

    CEMenuBuildGuard = YES;
    UIMenu *section = [UIMenu menuWithTitle:@"" image:nil identifier:CEExtensionMenuIdentifier options:UIMenuOptionsDisplayInline children:@[rename, exportMD]];
    CEMenuBuildGuard = NO;
    return [children arrayByAddingObject:section];
}

@implementation UIWindow (ChatGPTEnhancerTouch)
- (void)ce_sendEvent:(UIEvent *)event {
    NSSet<UITouch *> *touches = event.allTouches;
    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        CGPoint point = [touch locationInView:self];
        UIView *hit = [self hitTest:point withEvent:event];
        if (hit) { CELastTouchedView = hit; CELastTouchDate = [NSDate date]; }
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    [self contextChanged:nil];
}
- (UIButton *)button {
    if (_button) return _button;
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    _button.frame = CGRectMake(0, 0, 48, 44); _button.layer.cornerRadius = 14; _button.layer.masksToBounds = NO;
    _button.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.96];
    [_button setTitle:@"MD" forState:UIControlStateNormal]; _button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _button.layer.shadowColor = UIColor.blackColor.CGColor; _button.layer.shadowOpacity = 0.16; _button.layer.shadowRadius = 8; _button.layer.shadowOffset = CGSizeMake(0, 3);
    [_button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]; [_button addGestureRecognizer:pan];
    return _button;
}
- (void)contextChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL shouldShow = [CEConversationContext shared].conversationID.length > 0;
        if (!shouldShow) { [self.button removeFromSuperview]; self.window = nil; return; }
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
- (void)buttonTapped {
    NSString *cid = [CEConversationContext shared].conversationID; if (!cid.length) return;
    CEConversationRecord *record = [[CECatalog shared] recordForID:cid] ?: [CEConversationRecord new];
    if (!record.conversationID.length) record.conversationID = cid;
    if (!record.title.length) record.title = [CEConversationContext shared].title ?: @"当前会话";
    [CEFeatures exportRecord:record requireConfirmation:YES];
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
        [[CEFloatingButtonController shared] start];
    });
}
@end
