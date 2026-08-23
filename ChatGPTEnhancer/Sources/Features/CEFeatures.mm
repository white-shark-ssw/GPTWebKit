#import "CEFeatures.h"
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Export/CEMarkdownExporter.h"

@interface CEExportJob : NSObject
@property (nonatomic, strong) CEConversationRecord *record;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic) BOOL fetchFinished;
@property (nonatomic) BOOL userConfirmed;
@property (nonatomic, weak, nullable) UIAlertController *progressAlert;
@property (nonatomic, copy, nullable) NSString *progressMessage;
@end
@implementation CEExportJob @end

@implementation CEFeatures

+ (void)chooseFromCandidates:(NSArray<CEConversationRecord *> *)candidates title:(NSString *)title completion:(void (^)(CEConversationRecord *record))completion {
    if (!candidates.count) { CEShowToast(@"暂时无法识别这个会话，请稍后再试。"); return; }
    if (candidates.count == 1) { completion(candidates.firstObject); return; }
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:@"存在同名会话，请选择要操作的一项。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateStyle = NSDateFormatterShortStyle; formatter.timeStyle = NSDateFormatterShortStyle;
    for (CEConversationRecord *record in candidates) {
        NSString *suffix = record.updatedAt ? [formatter stringFromDate:record.updatedAt] : @"时间未知";
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ · %@", record.title, suffix] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { completion(record); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = vc.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
    [vc presentViewController:sheet animated:YES completion:nil];
}

+ (void)exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu {
    [self chooseFromCandidates:candidates title:@"导出 Markdown" completion:^(CEConversationRecord *record) { [self exportRecord:record requireConfirmation:!fromContextMenu]; }];
}

+ (void)exportRecord:(CEConversationRecord *)record requireConfirmation:(BOOL)requireConfirmation {
    if (!record.conversationID.length) { CEShowToast(@"无法识别会话 ID。"); return; }
    if (!requireConfirmation) { [self beginExportRecord:record]; return; }
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出 Markdown" message:[NSString stringWithFormat:@"确定导出当前《%@》会话吗？", record.title] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self beginExportRecord:record]; }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)beginExportRecord:(CEConversationRecord *)record {
    CEExportJob *job = [CEExportJob new]; job.record = record; job.filename = record.title;
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversation/%@", [record.conversationID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    [[CEAPIClient shared] getPath:path progress:^(NSString *message) {
        job.progressMessage = message;
        if (job.progressAlert) job.progressAlert.message = [NSString stringWithFormat:@"%@\n\n", message];
    } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        job.fetchFinished = YES; job.data = data; job.error = error;
        if (job.userConfirmed) [self finishExportJob:job];
    }];

    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *rename = [UIAlertController alertControllerWithTitle:@"重命名 Markdown" message:@"完整会话已在后台开始读取。" preferredStyle:UIAlertControllerStyleAlert];
    [rename addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = record.title; field.clearButtonMode = UITextFieldViewModeWhileEditing; field.autocorrectionType = UITextAutocorrectionTypeNo; field.spellCheckingType = UITextSpellCheckingTypeNo;
    }];
    [rename addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [rename addAction:[UIAlertAction actionWithTitle:@"导出" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [rename.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        job.filename = name.length ? name : record.title; job.userConfirmed = YES;
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
    job.progressAlert = progress; [vc presentViewController:progress animated:YES completion:nil];
}

+ (void)finishExportJob:(CEExportJob *)job {
    if (job.error || !job.data.length) {
        [job.progressAlert dismissViewControllerAnimated:YES completion:^{ [self showExportError:job.error ?: [NSError errorWithDomain:@"ChatGPTEnhancer" code:-70 userInfo:@{NSLocalizedDescriptionKey:@"完整会话没有返回数据。"}] record:job.record filename:job.filename]; }];
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
            if (job.progressAlert) [job.progressAlert dismissViewControllerAnimated:YES completion:present]; else present();
        });
    });
}

+ (void)showExportError:(NSError *)error record:(CEConversationRecord *)record filename:(NSString *)filename {
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self beginExportRecord:record]; }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(UIView *)sourceView {
    [self chooseFromCandidates:candidates title:@"重命名会话" completion:^(CEConversationRecord *record) { [self promptRenameRecord:record sourceView:sourceView]; }];
}

+ (void)promptRenameRecord:(CEConversationRecord *)record sourceView:(UIView *)sourceView {
    UIViewController *vc = CETopViewController(); if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名会话" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = record.title; field.clearButtonMode = UITextFieldViewModeWhileEditing; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
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
    CEShowToast(@"正在重命名…");
    [[CEAPIClient shared] patchPath:path jsonBody:@{@"title":newTitle} progress:^(NSString *message) { CEShowToast(message); } completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            UIViewController *vc = CETopViewController(); if (!vc) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self performRenameRecord:record newTitle:newTitle sourceView:sourceView]; }]];
            [vc presentViewController:alert animated:YES completion:nil]; return;
        }
        NSString *oldTitle = record.title; [[CECatalog shared] updateTitle:newTitle forConversationID:record.conversationID]; [self replaceVisibleText:oldTitle with:newTitle inView:CEKeyWindow()]; CEShowToast(@"✓ 已重命名");
    }];
}

+ (void)replaceVisibleText:(NSString *)oldText with:(NSString *)newText inView:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:oldText]) ((UILabel *)view).text = newText;
    if ([view.accessibilityLabel isEqualToString:oldText]) view.accessibilityLabel = newText;
    for (UIView *child in view.subviews) [self replaceVisibleText:oldText with:newText inView:child];
}
@end
