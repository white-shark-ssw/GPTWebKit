#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CEConversationRecord : NSObject
@property (nonatomic, copy) NSString *conversationID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSString *projectID;
@end

@interface CECatalog : NSObject
@property (nonatomic, readonly) BOOL refreshing;
+ (instancetype)shared;
- (void)start;
- (void)refreshIfPossible;
- (nullable CEConversationRecord *)recordForID:(NSString *)conversationID;
- (NSArray<CEConversationRecord *> *)recordsMatchingTitle:(NSString *)title;
- (NSArray<CEConversationRecord *> *)candidatesForView:(UIView *)view;
- (void)updateTitle:(NSString *)title forConversationID:(NSString *)conversationID;
@end

NS_ASSUME_NONNULL_END
