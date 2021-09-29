//
//  Copyright Yahoo 2021
//

#import "BGPriorityQueue.h"

#define ElementCount (CFBinaryHeapGetCount(_heap) + _unheapedElements.count)

CFComparisonResult bg_priorityQueueCompare(const void *ptr1, const void *ptr2, void *context) {
    CFComparisonResult(^comparisonBlock)(id _Nonnull, id _Nonnull) = *(__unsafe_unretained CFComparisonResult(^ *)(id _Nonnull, id _Nonnull))context;
    return comparisonBlock((__bridge id)ptr1, (__bridge id)ptr2);
}

@interface BGPriorityQueue<ObjectType> ()
@property (nonatomic, readonly, nonnull) CFBinaryHeapRef heap;
@property (nonatomic, readonly, nonnull) CFComparisonResult(^comparisonBlock)(id _Nonnull, id _Nonnull);
@property (nonatomic, readonly) CFBinaryHeapCompareContext compareContext;
@property (nonatomic, readonly) NSMutableArray<ObjectType> *unheapedElements;
@end

@implementation BGPriorityQueue

- (instancetype)init {
    return [self initWithComparisonBlock:nil];
}

- (instancetype)initWithComparisonBlock:(CFComparisonResult (^)(id _Nonnull, id _Nonnull))comparisonBlock {
    _comparisonBlock = comparisonBlock;
    
    CFBinaryHeapCallBacks callbacks = { .compare = &bg_priorityQueueCompare};
    CFBinaryHeapCompareContext context = { .info = &_comparisonBlock };
    _heap = CFBinaryHeapCreate(kCFAllocatorDefault, 0, &callbacks, &context);
    
    _unheapedElements = [NSMutableArray new];
    return self;
}

- (void)dealloc {
    CFRelease(_heap);
}

- (id _Nullable)top {
    if (ElementCount == 0) {
        return nil;
    }
    
    [self heapify];
    return (__bridge_transfer id)CFBinaryHeapGetMinimum(_heap);
}

- (id _Nullable)pop {
    if (ElementCount == 0) {
        return nil;
    }
    
    [self heapify];
    id top = (__bridge_transfer id)CFBinaryHeapGetMinimum(_heap);
    CFBinaryHeapRemoveMinimumValue(_heap);
    return top;
}

- (void)push:(id)object {
    [_unheapedElements addObject:object];
}

- (NSUInteger)count {
    return ElementCount;
}

- (void)heapify {
    if (_unheapedElements.count > 0) {
        for (id obj in _unheapedElements) {
            CFBinaryHeapAddValue(_heap, (__bridge_retained void *)obj);
        }
        [_unheapedElements removeAllObjects];
    }
}

- (void)needsResort {
    while (CFBinaryHeapGetCount(_heap) > 0) {
        id value = (__bridge_transfer id)CFBinaryHeapGetMinimum(_heap);
        CFBinaryHeapRemoveMinimumValue(_heap);
        [_unheapedElements addObject:value];
    }
}

@end
