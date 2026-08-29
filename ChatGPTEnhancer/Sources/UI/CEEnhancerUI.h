#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CEEnhancerUI : NSObject
+ (instancetype)shared;
- (void)start;
@end

NSObject * _Nullable CECaptureCurrentConversationUIReloadSnapshot(void);
BOOL CECurrentConversationUIReloadSnapshotHasContent(NSObject * _Nullable snapshot);
BOOL CECurrentConversationUIReloadSnapshotShowsRebuild(NSObject * _Nullable baseline, NSObject * _Nullable current);

NS_ASSUME_NONNULL_END
