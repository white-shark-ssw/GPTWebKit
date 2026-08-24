#import "CEFeatures.h"
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Export/CEMarkdownExporter.h"
#import "../Diagnostics/CEDiagnostics.h"
#import "../Diagnostics/CERecoveryDiagnostics.h"
#import "CEForegroundStreamRecovery.h"
#import "CEOrphanedConversationRecovery.h"

@interface CEExportJob : NSObject
@property (nonatomic, strong) CEConversationRecord *record;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic) BOOL fetchFinished;
@property (nonatomic) BOOL userConfirmed;
@property (nonatomic) BOOL userCancelled;
@property (nonatomic, weak, nullable) UIAlertController *progressAlert;
@property (nonatomic, weak, nullable) UIAlertController *renameAlert;
@property (nonatomic, copy, nullable) NSString *progressMessage;
@end
@implementation CEExportJob @end

static void CEFeatureAddAccessibilityText(NSMutableOrderedSet<NSString *> *out, id object) {
    if (!object || out.count >= 400) return;
    NSString *identifier = nil, *label = nil, *value = nil;
    @try {
        if ([object respondsToSelector:@selector(accessibilityIdentifier)]) identifier = [object accessibilityIdentifier];
        if ([object respondsToSelector:@selector(accessibilityLabel)]) label = [object accessibilityLabel];
        if ([object respondsToSelector:@selector(accessibilityValue)]) value = [object accessibilityValue];
    } @catch (__unused NSException *exception) {}
    for (NSString *text in @[identifier ?: @"", label ?: @"", value ?: @""]) {
        NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trim.length && trim.length <= 500) [out addObject:trim];
    }
}

static void CEFeatureCollectAccessibility(UIView *view, NSUInteger depth, NSMutableOrderedSet<NSString *> *out) {
    if (!view || depth > 14 || out.count >= 400) return;
    CEFeatureAddAccessibilityText(out, view);
    NSArray *elements = nil; @try { elements = view.accessibilityElements; } @catch (__unused NSException *exception) {}
    for (id element in elements ?: @[]) CEFeatureAddAccessibilityText(out, element);
    for (UIView *child in view.subviews) CEFeatureCollectAccessibility(child, depth + 1, out);
}

@implementation CEFeatures

+ (BOOL)isPlaceholderTitle:(NSString *)title { return !title.length || [title isEqualToString:@"当前会话"] || [title isEqualToString:@"ChatGPT Conversation"]; }

+ (NSString *)titleFromVisibleUI {
    UIWindow *window = CEKeyWindow(); if (!window) return nil;
    NSMutableOrderedSet<NSString *> *strings = [NSMutableOrderedSet orderedSet];
    CEFeatureCollectAccessibility(window, 0, strings);
    for (NSString *text in CECollectVisibleStrings(window, 12)) if (text.length) [strings addObject:text];

    static NSArray<NSRegularExpression *> *patterns; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *compiled = [NSMutableArray array];
        NSArray *raw = @[
            @"给\\s*[“\\\"「『]\\s*(.{2,160}?)\\s*[”\\\"」』]\\s*(?:发送消息|发消息)",
            @"Message\\s*[“\\\"]\\s*(.{2,160}?)\\s*[”\\\"]"
        ];
        for (NSString *pattern in raw) { NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil]; if (re) [compiled addObject:re]; }
        patterns = compiled;
    });

    for (NSString *text in strings) {
        for (NSRegularExpression *re in patterns) {
            NSTextCheckingResult *match = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
            if (match.numberOfRanges < 2) continue;
            NSString *title = [[text substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (title.length >= 2 && title.length <= 160) return title;
        }
    }
    return nil;
}

+ (NSString *)titleFromConversationData:(NSData *)data {
    if (!data.length) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *container = [root[@"mapping"] isKindOfClass:NSDictionary.class] ? root : ([root[@"conversation"] isKindOfClass:NSDictionary.class] ? root[@"conversation"] : nil);
    NSString *title = [container[@"title"] isKindOfClass:NSString.class] ? [container[@"title"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    return title.length ? title : nil;
}

+ (CEConversationRecord *)resolvedRecord:(CEConversationRecord *)record {
    if (!record.conversationID.length) return record;
    CEConversationRecord *catalog = [[CECatalog shared] recordForID:record.conversationID];
    if (catalog && ![self isPlaceholderTitle:catalog.title]) return catalog;
    NSData *cached = [[CECatalog shared] conversationDataForID:record.conversationID];
    NSString *title = [self titleFromConversationData:cached];
    if (!title.length && [[[CEConversationContext shared] conversationID] isEqualToString:record.conversationID]) title = [self titleFromVisibleUI];
    if (title.length) { record.title = title; [[CECatalog shared] updateTitle:title forConversationID:record.conversationID]; }
    return record;
}

+ (void)showUnresolvedDiagnostics {
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"暂时无法识别这个会话" message:@"当前版本已经成功接入官方长按菜单，但还没有拿到这条列表项对应的 conversation ID。可以复制一份不含 Token/Cookie 值的诊断信息给我。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制诊断" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { CECopyDiagnostics(CEKeyWindow(), nil); }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)chooseFromCandidates:(NSArray<CEConversationRecord *> *)candidates title:(NSString *)title completion:(void (^)(CEConversationRecord *record))completion {
    if (!candidates.count) { [self showUnresolvedDiagnostics]; return; }
    if (candidates.count == 1) { completion([self resolvedRecord:candidates.firstObject]); return; }
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:@"存在同名会话，请选择要操作的一项。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateStyle = NSDateFormatterShortStyle; formatter.timeStyle = NSDateFormatterShortStyle;
    for (CEConversationRecord *record in candidates) {
        NSString *suffix = record.updatedAt ? [formatter stringFromDate:record.updatedAt] : @"时间未知";
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ · %@", record.title, suffix] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { completion([self resolvedRecord:record]); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = vc.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
    [vc presentViewController:sheet animated:YES completion:nil];
}

+ (void)exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu {
    [self chooseFromCandidates:candidates title:@"导出 Markdown" completion:^(CEConversationRecord *record) { [self exportRecord:record requireConfirmation:!fromContextMenu]; }];
}

+ (void)exportRecord:(CEConversationRecord *)record requireConfirmation:(BOOL)requireConfirmation {
    record = [self resolvedRecord:record];
    if (!record.conversationID.length) { CEShowMessage(@"无法识别会话 ID。"); return; }
    if (!requireConfirmation) { [self beginExportRecord:record]; return; }
    UIViewController *vc = CETopViewController(); if (!vc) return;
    NSString *message = [self isPlaceholderTitle:record.title] ? @"确定导出当前会话吗？" : [NSString stringWithFormat:@"确定导出当前《%@》会话吗？", record.title];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出 Markdown" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self beginExportRecord:record]; }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)applyFetchedTitleForJob:(CEExportJob *)job {
    NSString *title = [self titleFromConversationData:job.data];
    if (!title.length) return;
    BOOL hadPlaceholder = [self isPlaceholderTitle:job.record.title];
    job.record.title = title;
    [[CECatalog shared] updateTitle:title forConversationID:job.record.conversationID];
    if (hadPlaceholder) job.filename = title;
    UIAlertController *rename = job.renameAlert;
    if (hadPlaceholder && rename.textFields.firstObject && !job.userConfirmed) rename.textFields.firstObject.text = title;
}

+ (void)beginExportRecord:(CEConversationRecord *)record {
    record = [self resolvedRecord:record];
    CEExportJob *job = [CEExportJob new]; job.record = record; job.filename = [self isPlaceholderTitle:record.title] ? @"ChatGPT Conversation" : record.title;

    NSData *cached = [[CECatalog shared] conversationDataForID:record.conversationID];
    if (cached.length) {
        job.fetchFinished = YES; job.data = cached; [self applyFetchedTitleForJob:job];
    } else {
        NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", [record.conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
        [[CEAPIClient shared] getPath:path progress:^(NSString *message) {
            job.progressMessage = message;
            if (job.progressAlert) job.progressAlert.message = [NSString stringWithFormat:@"%@\n\n", message];
        } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
            job.fetchFinished = YES; job.data = data; job.error = error; [self applyFetchedTitleForJob:job];
            if (job.userConfirmed && !job.userCancelled) [self finishExportJob:job];
        }];
    }

    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *rename = [UIAlertController alertControllerWithTitle:@"重命名 Markdown" message:cached.length ? @"已读取当前会话，可直接导出。" : @"正在尝试取得当前完整会话。" preferredStyle:UIAlertControllerStyleAlert];
    job.renameAlert = rename;
    [rename addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = job.filename; field.clearButtonMode = UITextFieldViewModeWhileEditing; field.autocorrectionType = UITextAutocorrectionTypeNo; field.spellCheckingType = UITextSpellCheckingTypeNo;
    }];
    [rename addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [rename addAction:[UIAlertAction actionWithTitle:@"导出" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [rename.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        job.filename = name.length ? name : job.filename; job.userConfirmed = YES;
        if (job.fetchFinished) [self finishExportJob:job]; else [self showProgressForJob:job];
    }]];
    [vc presentViewController:rename animated:YES completion:^{ [rename.textFields.firstObject selectAll:nil]; }];
}

+ (void)showProgressForJob:(CEExportJob *)job {
    UIViewController *vc = CETopViewController(); if (!vc) return;
    NSString *message = job.progressMessage.length ? job.progressMessage : @"正在获取完整会话并生成 Markdown…";
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在导出…" message:[NSString stringWithFormat:@"%@\n\n", message] preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; spinner.translatesAutoresizingMaskIntoConstraints = NO; [spinner startAnimating];
    [progress.view addSubview:spinner]; [NSLayoutConstraint activateConstraints:@[[spinner.centerXAnchor constraintEqualToAnchor:progress.view.centerXAnchor], [spinner.bottomAnchor constraintEqualToAnchor:progress.view.bottomAnchor constant:-18]]];
    [progress addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { job.userCancelled = YES; job.progressAlert = nil; }]];
    job.progressAlert = progress; [vc presentViewController:progress animated:YES completion:nil];
}

+ (void)finishExportJob:(CEExportJob *)job {
    if (job.userCancelled) return;
    if (job.error || !job.data.length) {
        NSError *failure = job.error ?: [NSError errorWithDomain:@"ChatGPTEnhancer" code:-70 userInfo:@{NSLocalizedDescriptionKey:@"完整会话没有返回数据。"}];
        void (^showError)(void) = ^{ [self showExportError:failure record:job.record filename:job.filename]; };
        if (job.progressAlert.presentingViewController) [job.progressAlert dismissViewControllerAnimated:YES completion:showError]; else showError();
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil; NSString *markdown = [CEMarkdownExporter markdownFromConversationData:job.data fallbackTitle:job.record.title error:&error];
        NSURL *url = markdown ? [CEMarkdownExporter writeMarkdown:markdown filename:job.filename error:&error] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^present)(void) = ^{
                if (!url) { [self showExportError:error ?: [NSError errorWithDomain:@"ChatGPTEnhancer" code:-71 userInfo:@{NSLocalizedDescriptionKey:@"Markdown 生成失败。"}] record:job.record filename:job.filename]; return; }
                UIViewController *vc = CETopViewController(); if (!vc) return;
                UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES]; picker.shouldShowFileExtensions = YES; [vc presentViewController:picker animated:YES completion:nil];
            };
            if (job.progressAlert.presentingViewController) [job.progressAlert dismissViewControllerAnimated:YES completion:present]; else present();
        });
    });
}

+ (void)showExportError:(NSError *)error record:(CEConversationRecord *)record filename:(NSString *)filename {
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制诊断" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { CECopyDiagnostics(CEKeyWindow(), nil); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self beginExportRecord:record]; }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)pullLatestCurrentConversation {
    NSString *conversationID = [CEConversationContext shared].conversationID;
    if (!conversationID.length) { CEShowMessage(@"无法识别当前会话。"); return; }
    CEPullLatestConversationResult(conversationID);
}

+ (void)reloadCurrentConversation {
    NSString *conversationID = [CEConversationContext shared].conversationID;
    if (!conversationID.length) { CEShowMessage(@"无法识别当前会话。"); return; }
    CECaptureFocusedActiveConversationDiagnostics(@"reload button before any navigation");
    CERecoveryDiagnosticMark(@"MANUAL RELOAD DIAGNOSTIC ONLY");
    CERecoveryDiagnosticLog(@"MANUAL-RELOAD", @"alpha25 diagnostic captured live state conversation=%@; destructive route/history replay disabled", conversationID);
    CEShowMessage(@"已采集当前会话状态；诊断版不会跳转页面。");
}

+ (void)renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView {
    [self chooseFromCandidates:candidates title:@"重命名会话" completion:^(CEConversationRecord *record) { [self promptRenameRecord:record sourceView:sourceView]; }];
}

+ (void)promptRenameRecord:(CEConversationRecord *)record sourceView:(UIView *)sourceView {
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名会话" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = [self isPlaceholderTitle:record.title] ? @"" : record.title; field.clearButtonMode = UITextFieldViewModeWhileEditing; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *newTitle = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!newTitle.length || [newTitle isEqualToString:record.title]) return;
        [self performRenameRecord:record newTitle:newTitle sourceView:sourceView];
    }]];
    [vc presentViewController:alert animated:YES completion:^{ [alert.textFields.firstObject selectAll:nil]; }];
}

+ (void)performRenameRecord:(CEConversationRecord *)record newTitle:(NSString *)newTitle sourceView:(UIView *)sourceView {
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", [record.conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    CEShowMessage(@"正在重命名…");
    [[CEAPIClient shared] patchPath:path jsonBody:@{@"title":newTitle} progress:^(NSString *message) { CEShowMessage(message); } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            UIViewController *vc = CETopViewController(); if (!vc) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"复制诊断" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { CECopyDiagnostics(sourceView ?: CEKeyWindow(), nil); }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self performRenameRecord:record newTitle:newTitle sourceView:sourceView]; }]];
            [vc presentViewController:alert animated:YES completion:nil]; return;
        }
        NSString *oldTitle = record.title; [[CECatalog shared] updateTitle:newTitle forConversationID:record.conversationID]; [self replaceVisibleText:oldTitle with:newTitle inView:CEKeyWindow()]; CEShowMessage(@"✓ 已重命名");
    }];
}

+ (void)replaceVisibleText:(NSString *)oldText with:(NSString *)newText inView:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:oldText]) ((UILabel *)view).text = newText;
    if ([view.accessibilityLabel isEqualToString:oldText]) view.accessibilityLabel = newText;
    for (UIView *child in view.subviews) [self replaceVisibleText:oldText with:newText inView:child];
}
@end
