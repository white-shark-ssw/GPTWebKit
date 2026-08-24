#import <Foundation/Foundation.h>

BOOL CEOrphanReselectConversation(NSString *conversationID);
void CEOrphanForceReloadConversation(NSString *conversationID, void (^completion)(BOOL success));
