//
//  Copyright Yahoo 2021
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TestOnDealloc : NSObject
@property (nonatomic) dispatch_block_t onDealloc;
- (instancetype)initWithDeallocBlock:(dispatch_block_t)deallocBlock;
@end

NS_ASSUME_NONNULL_END
