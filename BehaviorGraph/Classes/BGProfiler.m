//
//  Copyright Yahoo 2021
//

#if BGDEBUG==1
#import "BGProfiler.h"
#import "BGGraph+Private.h"

#import <objc/runtime.h>
#include <mach/mach_time.h>

#define NS_PER_MS 1000000.0


static BOOL assertUndeclaredDemands;
static BOOL testUndeclaredDemands;
static BOOL foundUndeclaredDemands;

@interface BGCycleStats : NSObject
@property (nonatomic) uint64_t totalTime;
@property (nonatomic) uint64_t count;
@property (nonatomic) uint64_t totalSortTime;
@property (nonatomic) uint64_t sortCount;
@end

@implementation BGCycleStats
@end

@interface BGSortStats : NSObject
@property (nonatomic) uint64_t totalTime;
@property (nonatomic) uint64_t count;
@end

@implementation BGSortStats
@end

@interface BGProfiler ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, BGCycleStats *> *cycleStats;
@property (nonatomic, readonly) uint64_t totalCycleTime;
@property (nonatomic, readonly) uint64_t cycleCount;

@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, BGSortStats *> *sortStats;
@property (nonatomic, readonly) uint64_t totalSortTime;
@property (nonatomic, readonly) uint64_t sortCount;

@property (nonatomic, readonly) NSMutableArray<NSNumber *> *currentCycleSortTimes;

- (void)addCycleWithImpulse:(NSString *)impulse time:(uint64_t)time;
- (void)addSortWithUnsortedCount:(uint64_t)unsortedCount time:(uint64_t)time;
@end

@interface BGResource (Profiler)
@end

@implementation BGResource (Profiler)

- (void)profiler_verifyDemands {
    // Looks at every access to ensure that things are being accessed properly in the graph.
    BGBehavior *currentBehavior = self.behavior.graph.currentBehavior;
    
    if (currentBehavior && self.behavior != currentBehavior && self.extent.addedToGraph && ![currentBehavior.demands containsObject:self]) {
        foundUndeclaredDemands = YES;
        if (assertUndeclaredDemands) {
            NSAssert(NO, @"Resource %@ (%p) must be a demanded or supplied by behavior %@ (%p) to read its value or event",
                     self.staticDebugName, self, currentBehavior.staticDebugName, currentBehavior);
        }
    }
}

- (id)profiler_value {
    [self profiler_verifyDemands];
    return [self profiler_value];
}

- (BGEvent *)profiler_event {
    [self profiler_verifyDemands];
    return [self profiler_event];
}

@end

@interface BGGraph ()
- (void)orderBehaviors;
- (void)processChanges:(dispatch_block_t)changeBlock impulse:(NSString *)impulse;
@end

@interface BGGraph (Profiler)
@end

@implementation BGGraph (Profiler)

- (void)profiler_action:(NSString * _Nullable)impulse requireSync:(BOOL)requireSync runBlock:(dispatch_block_t _Nonnull)changes {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    
    uint64_t start = mach_absolute_time();
    [self profiler_action:impulse requireSync:requireSync runBlock:changes];
    uint64_t end = mach_absolute_time();
    
    uint64_t duration = (end - start) * info.numer / info.denom;
    [BGProfiler.sharedInstance addCycleWithImpulse:impulse time:duration];
}

- (void)profiler_orderBehaviors {
    NSUInteger unsortedCount = self.needsOrdering.count;
    if (unsortedCount > 0) {
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        
        uint64_t start = mach_absolute_time();
        [self profiler_orderBehaviors];
        uint64_t end = mach_absolute_time();
        
        uint64_t duration = (end - start) * info.numer / info.denom;
        [BGProfiler.sharedInstance addSortWithUnsortedCount:unsortedCount time:duration];
    } else {
        [self profiler_orderBehaviors];
    }
}

@end

@implementation BGProfiler

static BGProfiler *sharedInstance;

+ (void)load {
    sharedInstance = [BGProfiler new];
    
    if ([NSProcessInfo.processInfo.arguments containsObject:@"-graphProfileTime"]) {
        {
            Method original = class_getInstanceMethod(BGGraph.class, NSSelectorFromString(@"_action:requireSync:changes:"));
            Method swizzled = class_getInstanceMethod(BGGraph.class, @selector(profiler_action:requireSync:runBlock:));
            method_exchangeImplementations(original, swizzled);
        }
        
        {
            Method original = class_getInstanceMethod(BGGraph.class, @selector(orderBehaviors));
            Method swizzled = class_getInstanceMethod(BGGraph.class, @selector(profiler_orderBehaviors));
            method_exchangeImplementations(original, swizzled);
        }
    }
    
    assertUndeclaredDemands = [NSProcessInfo.processInfo.arguments containsObject:@"-graphVerifyDemands"];
    testUndeclaredDemands = [NSProcessInfo.processInfo.environment[@"test_undeclared_demands"] isEqualToString:@"1"];
    
    if (assertUndeclaredDemands || testUndeclaredDemands) {
        {
            Method original = class_getInstanceMethod(BGResource.class, @selector(value));
            Method swizzled = class_getInstanceMethod(BGResource.class, @selector(profiler_value));
            method_exchangeImplementations(original, swizzled);
        }
        
        {
            Method original = class_getInstanceMethod(BGResource.class, @selector(event));
            Method swizzled = class_getInstanceMethod(BGResource.class, @selector(profiler_event));
            method_exchangeImplementations(original, swizzled);
        }
    }
}

+ (BGProfiler *)sharedInstance {
    return sharedInstance;
}

+ (BOOL)testUndeclaredDemands {
    return testUndeclaredDemands;
}

+ (BOOL)foundUndeclaredDemands {
    return foundUndeclaredDemands;
}

- (instancetype)init {
    _cycleStats = [NSMutableDictionary new];
    _sortStats = [NSMutableDictionary new];
    _currentCycleSortTimes = [NSMutableArray new];
    return self;
}

- (void)addCycleWithImpulse:(NSString *)impulse time:(uint64_t)time {
    impulse = impulse ?: @"none";
    BGCycleStats *stats = _cycleStats[impulse];
    if (!stats) {
        stats = [BGCycleStats new];
        _cycleStats[impulse] = stats;
    }
    stats.totalTime += time;
    ++stats.count;
    
    _totalCycleTime += time;
    ++_cycleCount;
    
    for (NSNumber *sortTime in _currentCycleSortTimes) {
        ++stats.sortCount;
        stats.totalSortTime += sortTime.unsignedLongLongValue;
    }
    [_currentCycleSortTimes removeAllObjects];
}

- (void)addSortWithUnsortedCount:(uint64_t)unsortedCount time:(uint64_t)time {
    BGSortStats *stats = _sortStats[@(unsortedCount)];
    if (!stats) {
        stats = [BGSortStats new];
        _sortStats[@(unsortedCount)] = stats;
    }
    stats.totalTime += time;
    ++stats.count;
    
    _totalSortTime += time;
    ++_sortCount;
    
    [_currentCycleSortTimes addObject:@(time)];
}

- (NSString *)cycleTimeStats {
    if (![[[NSProcessInfo processInfo] arguments] containsObject:@"-graphProfileTime"]) {
        return @"Use run argument '-graphProfileTime' to enable behavior graph time profiling.";
    }
    
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    
    NSString *(^newLine)(NSString *, NSString *, NSString *, NSString *, NSString *, NSString *) = ^NSString *(NSString *name, NSString *averageTime, NSString *totalTime, NSString *count, NSString *sortTime, NSString *sortCount) {
        NSMutableString *string = [NSMutableString new];
        [string appendString:name];
        for (int i = 0; i < 140 - (NSInteger)name.length - (NSInteger)averageTime.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:averageTime];
        
        for (int i = 0; i < 20 - (NSInteger)totalTime.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:totalTime];
        
        for (int i = 0; i < 20 - (NSInteger)count.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:count];
        
        for (int i = 0; i < 20 - (NSInteger)sortTime.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:sortTime];
        
        for (int i = 0; i < 20 - (NSInteger)sortCount.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:sortCount];
        
        return string;
    };
    
    [lines addObject:newLine(@"Impulse", @"Avg (ms)", @"Total (ms)", @"Count", @"Sort Time", @"Sort Count")];
    for (NSString *name in [_cycleStats.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString * _Nonnull obj1, NSString * _Nonnull obj2) {
        NSTimeInterval time1 = ({ BGCycleStats *stats = _cycleStats[obj1]; stats.totalTime / (double)stats.count; });
        NSTimeInterval time2 = ({ BGCycleStats *stats = _cycleStats[obj2]; stats.totalTime / (double)stats.count; });
        if (time1 > time2) {
            return NSOrderedAscending;
        } else if (time1 < time2) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }]) {
        BGCycleStats *cycle = _cycleStats[name];
        [lines addObject:newLine(name, [NSString stringWithFormat:@"%f", cycle.totalTime / 1000000 / (double)cycle.count], [NSString stringWithFormat:@"%f", cycle.totalTime / 1000000.0], [NSString stringWithFormat:@"%llu", cycle.count], [NSString stringWithFormat:@"%f", cycle.totalSortTime / NS_PER_MS], [NSString stringWithFormat:@"%llu", cycle.sortCount])];
    }
    [lines addObject:newLine(@"Total", _cycleCount > 0 ? [NSString stringWithFormat:@"%f", _totalCycleTime / 1000000 / (double)_cycleCount] : @"0", [NSString stringWithFormat:@"%f", _totalCycleTime / 1000000.0], [NSString stringWithFormat:@"%llu", _cycleCount], [NSString stringWithFormat:@"%f", _totalSortTime / NS_PER_MS], [NSString stringWithFormat:@"%llu", _sortCount])];
    
    return [@"\n" stringByAppendingString:[lines componentsJoinedByString:@"\n"]];
}

- (NSString *)sortTimeStats {
    if (![[[NSProcessInfo processInfo] arguments] containsObject:@"-graphProfileTime"]) {
        return @"Use run argument '-graphProfileTime' to enable behavior graph time profiling.";
    }
    
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    
    NSString *(^newLine)(NSString *, NSString *, NSString *, NSString *) = ^NSString *(NSString *unsortedCount, NSString *averageTime, NSString *totalTime, NSString *count) {
        NSMutableString *string = [NSMutableString new];
        for (int i = 0; i < 20 - (NSInteger)unsortedCount.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:unsortedCount];
        
        for (int i = 0; i < 20 - (NSInteger)averageTime.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:averageTime];
        
        for (int i = 0; i < 20 - (NSInteger)totalTime.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:totalTime];
        
        for (int i = 0; i < 20 - (NSInteger)count.length; ++i) {
            [string appendString:@" "];
        }
        [string appendString:count];
        
        return string;
    };
    
    [lines addObject:newLine(@"# Behaviors Sorted", @"Avg (ms)", @"Total (ms)", @"Count")];
    for (NSNumber *unsortedCount in [_sortStats.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSNumber * _Nonnull obj1, NSNumber * _Nonnull obj2) {
        NSTimeInterval time1 = ({ BGSortStats *stats = _sortStats[obj1]; stats.totalTime / (double)stats.count; });
        NSTimeInterval time2 = ({ BGSortStats *stats = _sortStats[obj2]; stats.totalTime / (double)stats.count; });
        if (time1 > time2) {
            return NSOrderedAscending;
        } else if (time1 < time2) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }]) {
        BGSortStats *cycle = _sortStats[unsortedCount];
        [lines addObject:newLine([NSString stringWithFormat:@"%llu", unsortedCount.unsignedLongLongValue], [NSString stringWithFormat:@"%f", cycle.totalTime / NS_PER_MS / (double)cycle.count], [NSString stringWithFormat:@"%f", cycle.totalTime / NS_PER_MS], [NSString stringWithFormat:@"%llu", cycle.count])];
    }
    [lines addObject:newLine(@"Total", _sortCount > 0 ? [NSString stringWithFormat:@"%f", _totalSortTime / NS_PER_MS / (double)_sortCount] : @"0", [NSString stringWithFormat:@"%f", _totalSortTime / NS_PER_MS], [NSString stringWithFormat:@"%llu", _sortCount])];
    
    return [@"\n" stringByAppendingString:[lines componentsJoinedByString:@"\n"]];
}

@end

#endif
