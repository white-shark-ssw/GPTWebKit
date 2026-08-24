#import <Foundation/Foundation.h>
#import "../Core/CECore.h"
#import "CERecoveryDiagnostics.h"

__attribute__((constructor)) static void CEInPlaceRecoveryProbeHookEntry(void) {
    @autoreleasepool {
        if (!CETargetApp()) return;
        CERecoveryDiagnosticLog(@"INPLACE33-HOOK", @"automatic current-conversation GET probe disabled; manual diagnostics retained");
    }
}
