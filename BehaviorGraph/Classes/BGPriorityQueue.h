//
//  Copyright Yahoo 2021
//

#import <Foundation/Foundation.h>

@interface BGPriorityQueue<ObjectType> : NSObject
@property (nonatomic, readonly, nullable) ObjectType top;
@property (nonatomic, readonly) NSUInteger count;
- (instancetype _Nonnull)initWithComparisonBlock:(CFComparisonResult(^ _Nullable)(ObjectType _Nonnull obj1, ObjectType _Nonnull obj2))comparisonFunction NS_DESIGNATED_INITIALIZER;
- (ObjectType _Nullable)pop;
- (void)push:(ObjectType _Nonnull)object;
- (void)needsResort;
@end
