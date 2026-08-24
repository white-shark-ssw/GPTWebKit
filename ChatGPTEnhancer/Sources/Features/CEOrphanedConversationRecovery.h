#import <Foundation/Foundation.h>

BOOL CEOrphanReselectConversation(NSString *conversationID);
void CEOrphanRefreshConversation(NSString *conversationID, void (^completion)(BOOL success));
void CEOrphanForceReloadConversation(NSString *conversationID, void (^completion)(BOOL success));
NSString *CEOrphanedConversationRecoveryDiagnosticsSnapshot(void);
