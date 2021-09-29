//
//  Copyright Yahoo 2021
//

#import "TestOnDealloc.h"

@implementation TestOnDealloc
- (instancetype)initWithDeallocBlock:(dispatch_block_t)deallocBlock {
    _onDealloc = deallocBlock;
    return self;
}

- (void)dealloc {
    dispatch_block_t block = _onDealloc;
    if (block) {
        _onDealloc = nil;
        block();
    }
}
@end
