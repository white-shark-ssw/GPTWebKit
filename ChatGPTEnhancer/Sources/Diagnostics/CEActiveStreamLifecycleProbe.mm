#import <Foundation/Foundation.h>
#import "../Core/CECore.h"
#import "CERecoveryDiagnostics.h"

__attribute__((constructor)) static void CEActiveStreamLifecycleProbeEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        CERecoveryDiagnosticLog(@"INPLACE33-LIFECYCLE", @"automatic heavy lifecycle probe disabled; manual diagnostics retained");
    }
}
