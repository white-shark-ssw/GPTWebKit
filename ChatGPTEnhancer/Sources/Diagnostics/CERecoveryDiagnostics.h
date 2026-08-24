#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void CERecoveryDiagnosticMark(NSString *name);
void CERecoveryDiagnosticLog(NSString *category, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
NSString *CERecoveryDiagnosticsReport(void);

NS_ASSUME_NONNULL_END
