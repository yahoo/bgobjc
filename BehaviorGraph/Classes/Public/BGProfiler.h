//
//  Copyright Yahoo 2021
//

#if BGDEBUG

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BGProfiler : NSObject
@property (nonatomic, readonly, class) BGProfiler *sharedInstance;
@property (nonatomic, readonly, class) BOOL testUndeclaredDemands;
@property (nonatomic, readonly, class) BOOL foundUndeclaredDemands;
- (NSString *)cycleTimeStats;
- (NSString *)sortTimeStats;
@end

NS_ASSUME_NONNULL_END

#endif
