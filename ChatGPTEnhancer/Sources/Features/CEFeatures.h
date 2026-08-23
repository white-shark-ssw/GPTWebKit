#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Storage/CECatalog.h"

NS_ASSUME_NONNULL_BEGIN

@interface CEFeatures : NSObject
+ (void)exportCandidates:(NSArray<CEConversationRecord *> *)candidates fromContextMenu:(BOOL)fromContextMenu;
+ (void)exportRecord:(CEConversationRecord *)record requireConfirmation:(BOOL)requireConfirmation;
+ (void)renameCandidates:(NSArray<CEConversationRecord *> *)candidates sourceView:(nullable UIView *)sourceView;
@end

NS_ASSUME_NONNULL_END
