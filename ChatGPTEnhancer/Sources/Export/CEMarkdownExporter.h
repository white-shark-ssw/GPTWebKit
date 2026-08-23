#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CEMarkdownExporter : NSObject
+ (nullable NSString *)markdownFromConversationData:(NSData *)data fallbackTitle:(NSString *)fallbackTitle error:(NSError **)error;
+ (nullable NSURL *)writeMarkdown:(NSString *)markdown filename:(NSString *)filename error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
