//
//  Copyright Yahoo 2021
//

#import "BGGraph.h"
#import "BGPriorityQueue.h"
#import <os/signpost.h>

static NSObject * _Nonnull NullPushedValue;

typedef NS_ENUM(NSInteger, BGOrderingState) {
    BGOrderingStateUnordered,
    BGOrderingStateOrdering,
    BGOrderingStateOrdered,
};

typedef NS_ENUM(NSInteger, BGResourceValuePersistence) {
    BGResourcePersistent,
    BGResourceTransient,
    BGResourceTransientTrace,
};


@interface BGEvent ()
- (instancetype _Nonnull)initWithImpulse:(NSString * _Nullable )impulse sequence:(NSUInteger)sequence timestamp:(NSDate * _Nonnull)timestamp;
@end

@interface BGResource<__covariant ValueType> () {
    @protected
    __weak BGGraph *_graph;
    __weak BGExtent *_extent;
    __weak BGBehavior *_behavior;
    NSHashTable<BGBehavior *> *_subsequents;
    NSString *_staticDebugName;
}
@property (nonatomic, readwrite, weak, nullable) BGGraph *graph;
@property (nonatomic, readwrite, weak, nullable) BGExtent *extent;
@property (nonatomic, readwrite, weak, nullable) BGBehavior *behavior;
@property (nonatomic, readonly, nonnull) NSHashTable<BGBehavior *> *subsequents;
@property (nonatomic, nullable) void (^capturedInitialUpdate)(void);
@property (nonatomic, readonly) BOOL traced;
@property (nonatomic, readonly) BGResourceValuePersistence valuePersistence;
@property (nonatomic, nullable) ValueType previousValue;
@property (nonatomic, nullable) BGEvent *previousEvent;
- (instancetype _Nonnull)initWithExtent:(BGExtent * _Nonnull)extent value:(ValueType _Nullable)value event:(BGEvent * _Nullable)event;
- (void)_updateValue:(ValueType _Nullable)value;
- (void)_forceUpdateValue:(ValueType _Nullable)value;
- (void)clearTransient;
@end


@interface BGMoment<__covariant ValueType> ()
@end

@interface BGState<__covariant ValueType> ()
@end

@interface BGBehavior ()
@property (nonatomic, readonly, nonnull) NSHashTable<BGResource *> *supplies;
@property (nonatomic, readwrite, nullable) BGGraph *graph;
@property (nonatomic, readwrite, weak, nullable) BGExtent *extent;
@property (nonatomic, nullable) NSMutableArray<BGResource *> *modifiedDemands;
@property (nonatomic, readonly, nullable) NSHashTable<BGResource *> *demands;
@property (nonatomic) NSUInteger removedSequence;
@property (nonatomic) NSUInteger lastUpdateSequence;
@property (nonatomic) NSUInteger order;
@property (nonatomic) BGOrderingState orderingState;
@property (nonatomic) NSUInteger enqueuedSequence;
@end

@interface BGAction : NSObject
@property (nonatomic, nullable) NSString *name;
@property (nonatomic, nonnull) dispatch_block_t block;
- (instancetype _Nonnull)initWithName:(NSString * _Nullable)name block:(dispatch_block_t _Nonnull)block;
@end

@interface BGSideEffect : NSObject {
@protected
    NSString * _Nullable _name;
    BGEvent * _Nonnull _event;
}
@property (nonatomic, readonly, nullable) NSString *name;
@property (nonatomic, readonly, nonnull) BGEvent *event;
- (void)run;
@end

@interface BGBehaviorSideEffect : BGSideEffect
@property (nonatomic, readonly, nonnull) BGExtent *extent;
@property (nonatomic, readonly, nonnull) void(^block)(BGExtent * _Nonnull extent);
- (instancetype _Nonnull)initWithName:(NSString * _Nullable)name event:(BGEvent * _Nonnull)event extent:(BGExtent * _Nonnull)extent block:(void(^ _Nonnull)(BGExtent * _Nullable))block;
@end

@interface BGGraphSideEffect : BGSideEffect
@property (nonatomic, readonly, nonnull) dispatch_block_t block;
- (instancetype _Nonnull)initWithName:(NSString * _Nullable)name event:(BGEvent * _Nonnull)event block:(dispatch_block_t _Nonnull)block;
@end

@interface BGEventLoopState : NSObject
@property (nonatomic, nonnull) BGEvent *event;
@property (nonatomic, readonly) NSUInteger sequence;
@property (nonatomic) unsigned long long eventSid;
@property (nonatomic) BOOL processingAction;
@property (nonatomic) BOOL processingChanges;
@end

@interface BGGraph ()
@property (nonatomic, nullable) BGEventLoopState *eventLoopState;
@property (nonatomic, readonly) NSUInteger sequence;
@property (nonatomic, readonly) BOOL processingAction;
@property (nonatomic, readonly) BOOL processingChanges;
@property (nonatomic) NSUInteger eventLoopDrivers;
@property (nonatomic, nonnull) NSMutableSet<BGBehavior *> *needsOrdering;
@property (nonatomic, readonly, nonnull) NSMutableArray<dispatch_block_t> *afterChanges;
@property (nonatomic, readonly, nonnull) NSMutableSet<BGBehavior *> *untrackedBehaviors;
@property (nonatomic, readonly, nonnull) NSMutableSet<BGBehavior *> *modifiedDemands;
@property (nonatomic, readonly, nonnull) NSMutableArray<BGResource *> *updatedTransientResources;
@property (nonatomic, readonly, nonnull) NSMutableArray<id> *deferredRelease;
@property (nonatomic, readonly, nonnull) BGPriorityQueue<BGBehavior *> *behaviorQueue;
@property (nonatomic, readonly, nullable) os_log_t aclog;
@property (nonatomic, readonly, nullable) os_log_t splog;

@property (nonatomic, readonly, nullable) NSMutableArray<BGAction *> *actionQueue;
@property (nonatomic, readonly, nullable) NSMutableArray<BGSideEffect *> *sideEffectQueue;

- (void)submitToQueue:(BGBehavior * _Nonnull)subsequent;
- (void)removeBehavior:(BGBehavior * _Nonnull)behavior;
- (void)trackTransient:(BGResource * _Nonnull)rez;
@end

@interface BGDynamicLinks ()
@property (nonatomic, nullable) NSArray<BGResource *> *demandSwitches;
@property (nonatomic, nullable) NSArray<BGResource *> *supplySwitches;
@property (nonatomic, nullable) void (^dynamicDemands)(NSMutableArray<BGResource*> * _Nonnull demands, id _Nonnull extent);
@property (nonatomic, nullable) void (^dynamicSupplies)(NSMutableArray<BGResource*> * _Nonnull supplies, id _Nonnull extent);
@end

@interface BGExtent ()
@property (nonatomic, nullable) BGEvent *addedToGraph;
@property (nonatomic, readonly, nullable) NSMutableSet<BGBehavior *> *allBehaviors;
@property (nonatomic, readonly, nullable) NSMutableSet<BGResource *> *allResources;
- (void)addBehavior:(BGBehavior * _Nonnull)behavior;
- (void)addResource:(BGResource * _Nonnull)resource;
- (void)nameComponents;
@end
