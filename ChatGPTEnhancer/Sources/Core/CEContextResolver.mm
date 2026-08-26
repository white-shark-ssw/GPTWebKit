#import <Foundation/Foundation.h>
#import "CECore.h"

NSString *CERefreshVisibleConversationContext(void) { return [CEConversationContext shared].conversationID; }
