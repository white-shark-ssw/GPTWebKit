#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void CEConversationIdentityTraceStart(void);
BOOL CEConversationIdentityTraceIsRecording(void);
void CEConversationIdentityTraceBegin(void);
NSURL * _Nullable CEConversationIdentityTraceFinish(void);
void CEConversationIdentityTraceLog(NSString *category, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
void CEConversationIdentityTraceLogRequest(NSURLRequest *request);
void CEConversationIdentityTraceLogResponse(NSURLRequest *request, NSURLResponse * _Nullable response, NSError * _Nullable error);

NS_ASSUME_NONNULL_END
