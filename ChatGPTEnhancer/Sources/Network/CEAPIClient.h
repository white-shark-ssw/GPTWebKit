#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CEAPIProgressBlock)(NSString *message);
typedef void (^CEAPICompletionBlock)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error);

@interface CEAPIClient : NSObject
+ (instancetype)shared;
- (BOOL)isReady;
- (void)getPath:(NSString *)path progress:(nullable CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion;
- (void)patchPath:(NSString *)path jsonBody:(NSDictionary *)body progress:(nullable CEAPIProgressBlock)progress completion:(CEAPICompletionBlock)completion;
@end

NS_ASSUME_NONNULL_END
