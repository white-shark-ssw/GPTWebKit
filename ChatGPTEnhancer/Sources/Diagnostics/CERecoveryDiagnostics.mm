#import "CERecoveryDiagnostics.h"
#import "CEInPlaceRecoveryProbe.h"

static NSMutableArray<NSString *> *CERecoveryDiagnosticLines = nil;
static NSUInteger CERecoveryDiagnosticSequence = 0;

static NSMutableArray<NSString *> *CERecoveryDiagnosticStorage(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ CERecoveryDiagnosticLines = [NSMutableArray array]; });
    return CERecoveryDiagnosticLines;
}

static void CERecoveryDiagnosticAppend(NSString *category, NSString *message) {
    if (!message.length) return;
    long long timestamp = (long long)(NSDate.date.timeIntervalSince1970 * 1000.0);
    @synchronized (CERecoveryDiagnosticStorage()) {
        NSUInteger sequence = ++CERecoveryDiagnosticSequence;
        [CERecoveryDiagnosticLines addObject:[NSString stringWithFormat:@"%06lu %lld %@ | %@", (unsigned long)sequence, timestamp, category.length ? category : @"RECOVERY", message]];
        while (CERecoveryDiagnosticLines.count > 260) [CERecoveryDiagnosticLines removeObjectAtIndex:0];
    }
}

void CERecoveryDiagnosticMark(NSString *name) {
    CERecoveryDiagnosticAppend(@"MARK", [NSString stringWithFormat:@"========== %@ ==========", name.length ? name : @"event"]);
}

void CERecoveryDiagnosticLog(NSString *category, NSString *format, ...) {
    if (!format.length) return;
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    CERecoveryDiagnosticAppend(category, message);
}

NSString *CERecoveryDiagnosticsReport(void) {
    NSString *journal = nil;
    @synchronized (CERecoveryDiagnosticStorage()) { journal = CERecoveryDiagnosticLines.count ? [CERecoveryDiagnosticLines componentsJoinedByString:@"\n"] : @"<no recovery events captured>"; }
    NSString *probe = CEInPlaceRecoveryProbeSnapshot();
    return [NSString stringWithFormat:@"%@\n\n[In-place recovery probe snapshot]\n%@", journal, probe.length ? probe : @"<not captured>"];
}
