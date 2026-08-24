#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *CEDiagnosticsReport(UIView * _Nullable sourceView, NSString * _Nullable contextIdentifier);
void CECopyDiagnostics(UIView * _Nullable sourceView, NSString * _Nullable contextIdentifier);
void CEInstallActiveConversationDiagnostics(void);

NS_ASSUME_NONNULL_END
