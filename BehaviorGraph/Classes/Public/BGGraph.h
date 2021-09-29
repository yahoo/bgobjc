//
//  Copyright Yahoo 2021
//

#import <Foundation/Foundation.h>

@class BGBehavior;
@class BGGraph;

@class BGExtent;

@interface BGEvent : NSObject
@property (nonatomic, readonly) NSUInteger sequence;
@property (nonatomic, readonly, nonnull) NSDate *timestamp;
@property (nonatomic, readonly, nullable) NSString *impulse;
@property (nonatomic, readonly, class, nonnull) BGEvent *unknownPast;
- (BOOL)happenedSince:(NSUInteger)since;
@end


@interface BGResource<__covariant ValueType> : NSObject
@property (nonatomic, readonly, weak, nullable) BGGraph *graph;
@property (nonatomic, readonly, weak, nullable) BGExtent *extent;
@property (nonatomic, readonly, weak, nullable) BGBehavior *behavior;
@property (nonatomic, readonly, nullable) BGEvent *added;
@property (nonatomic, nullable) NSString *staticDebugName;

@property (nonatomic, readonly, nullable) ValueType value;
@property (nonatomic, readonly, nullable) ValueType traceValue;
@property (nonatomic, readonly, nonnull) BGEvent *event;
@property (nonatomic, readonly, nonnull) BGEvent *traceEvent;

@property (nonatomic, readonly) BOOL justAdded;
@property (nonatomic, readonly) BOOL justUpdated;
@property (nonatomic, readonly) BOOL justUpdatedToSomething;
@property (nonatomic, readonly) BOOL hasUpdated;
@property (nonatomic, readonly) BOOL traceHasUpdated;
- (BOOL)hasUpdatedSince:(BGResource * _Nonnull)since;
- (instancetype _Nonnull)initWithExtent:(BGExtent * _Nonnull)extent;
- (instancetype _Nonnull)init NS_UNAVAILABLE;
+ (instancetype _Nonnull)new NS_UNAVAILABLE;
- (BOOL)justUpdatedTo:(ValueType _Nullable)toValue;
@end

@interface BGMoment<__covariant ValueType> : BGResource<ValueType>
- (void)update;
- (void)updateValue:(ValueType _Nullable)value;
@end

@interface BGState<__covariant ValueType> : BGResource<ValueType>
- (instancetype _Nonnull)initWithExtent:(BGExtent * _Nonnull)extent value:(ValueType _Nullable)value NS_DESIGNATED_INITIALIZER;
- (void)updateValue:(ValueType _Nullable)value;
- (void)updateValueForce:(ValueType _Nullable)value;
- (BOOL)justUpdatedFrom:(ValueType _Nullable)fromValue;
- (BOOL)justUpdatedTo:(ValueType _Nullable)toValue from:(ValueType _Nullable)fromValue;
@end

@interface BGBehavior : NSObject
@property (nonatomic, nullable) void(^runBlock)(BGExtent * _Nonnull extent);
@property (nonatomic, nullable) NSString *staticDebugName;
@property (nonatomic, readonly, weak, nullable) BGGraph *graph;
@property (nonatomic, readonly, weak, nullable) BGExtent *extent;
- (instancetype _Nonnull)initWithExtent:(BGExtent * _Nonnull)extent
                                demands:(NSArray<BGResource *> * _Nullable)demands
                               supplies:(NSArray<BGResource *> * _Nullable)supplies
                               runBlock:(void(^_Nullable)(BGExtent * _Nonnull extent))runBlock;
- (void)setDemands:(NSArray<BGResource *> * _Nullable)demands;
- (void)addDemand:(BGResource * _Nullable)demand;
- (void)removeDemand:(BGResource * _Nullable)demand;

- (void)setSupplies:(NSArray<BGResource *> * _Nullable)supplies;
@end

@protocol BGDateProvider<NSObject>
- (NSDate * _Nonnull)bg_currentDate;
@end

@interface BGGraph : NSObject
@property (nonatomic, readonly, nonnull) BGBehavior *mainNode;
@property (nonatomic, readonly, nullable) BGEvent *currentEvent;
@property (nonatomic, readonly, nullable) BGEvent *lastEvent;
@property (nonatomic, readonly, nonnull) BGState<BGEvent *> *currentEventResource;
@property (nonatomic, weak, nullable) id<BGDateProvider> dateProvider;
@property (nonatomic, readonly, nonnull) BGExtent *rootExtent;
@property (nonatomic, readonly, nullable) BGBehavior * currentBehavior;
@property (nonatomic) BOOL defaultRequireSync;
@property (nonatomic) BOOL assertOnLeakedSideEffects;

- (void)action:(NSString * _Nullable)impulse runBlock:(dispatch_block_t _Nonnull)changes;
- (void)action:(NSString * _Nullable)impulse requireSync:(BOOL)requireSync runBlock:(dispatch_block_t _Nonnull)changes;
- (void)sideEffect:(NSString * _Nullable)name runBlock:(dispatch_block_t _Nonnull)block;
@end

@interface BGDynamicLinks<__covariant ExtentType> : NSObject
- (void)demandSwitches:(NSArray<BGResource *> * _Nonnull)switches
             resources:(void(^ _Nullable)(NSMutableArray<BGResource *> * _Nonnull demands, ExtentType _Nonnull extent))resources;

- (void)supplySwitches:(NSArray<BGResource *> * _Nonnull)switches
             resources:(void(^ _Nullable)(NSMutableArray<BGResource *> * _Nonnull supplies, ExtentType _Nonnull extent))resources;
@end

@interface BGExtent<__covariant SubType> : NSObject
@property (nonatomic, readonly, weak, nullable) BGGraph *graph;
@property (nonatomic, readonly, nonnull) BGMoment *added;
@property (nonatomic, readonly, nullable) NSString *debugHere;

- (instancetype _Nonnull)initWithGraph:(BGGraph * _Nonnull)graph NS_DESIGNATED_INITIALIZER;
- (instancetype _Nonnull)init NS_UNAVAILABLE;
+ (instancetype _Nonnull)new NS_UNAVAILABLE;
- (void)addToGraph;
- (void)removeFromGraph;
- (BGBehavior * _Nonnull)behaviorWithDemands:(NSArray<BGResource *> * _Nullable)demands
                                    supplies:(NSArray<BGResource *> * _Nullable)supplies
                                    runBlock:(void(^_Nullable)(SubType _Nonnull extent))runBlock;

- (BGBehavior * _Nonnull)dynamicBehaviorWithDemands:(NSArray<BGResource *> * _Nullable)staticDemands
                                           supplies:(NSArray<BGResource *> * _Nullable)staticSupplies
                                           dynamics:(void(^ _Nullable)(BGDynamicLinks<SubType> * _Nonnull dynamics, SubType _Nonnull extent))dynamicBlock
                                           runBlock:(void(^_Nullable)(SubType _Nonnull extent))runBlock;

- (void)sideEffect:(NSString * _Nullable)name runBlock:(void(^ _Nonnull)(SubType _Nonnull extent))block;
- (BGMoment * _Nonnull)moment;
- (BGResource * _Nonnull)resource;
- (BGState * _Nonnull)stateWithValue:(id _Nullable)value;
- (void)action:(NSString * _Nullable)impulse requireSync:(BOOL)requireSync runBlock:(dispatch_block_t _Nonnull)changes;
@end


