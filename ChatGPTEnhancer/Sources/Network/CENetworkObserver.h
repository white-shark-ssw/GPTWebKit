#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CENetworkObserver : NSObject
@property (nonatomic, strong, nullable, readonly) NSURLRequest *requestTemplate;
@property (nonatomic, copy, nullable, readonly) NSString *baseOrigin;
@property (nonatomic, copy, readonly) NSSet<NSString *> *knownProjectIDs;
+ (instancetype)shared;
- (void)start;
- (BOOL)hasUsableTemplate;
@end

NS_ASSUME_NONNULL_END
