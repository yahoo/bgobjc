//
//  Copyright Yahoo 2021
//

#import "BGGraph+Private.h"
#import <objc/runtime.h>

#define PriorlessOrder 0

BOOL bg_equal(NSObject *obj1, NSObject *obj2) {
    return (obj1 && obj2 && [obj1 isEqual:obj2]) || (!obj1 && !obj2);
}

static BGEvent* BGUnknownPast;

@implementation BGEvent

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (self == BGEvent.class) {
            BGUnknownPast = [[BGEvent alloc] initWithImpulse:@"UnknownPast" sequence:0 timestamp:[NSDate dateWithTimeIntervalSince1970:0]];
        }
    });
}

+ (BGEvent *)unknownPast {
    return BGUnknownPast;
}

- (instancetype _Nonnull)initWithImpulse:(NSString *)impulse sequence:(NSUInteger)sequence timestamp:(NSDate * _Nonnull)timestamp {
    self = [super init];
    _impulse = impulse;
    _sequence = sequence;
    _timestamp = timestamp;
    return self;
}

- (BOOL)happenedSince:(NSUInteger)since {
    return _sequence > 0 && _sequence >= since;
}

- (NSString *)description {
    return self.debugDescription;
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@:%p (%lu), %@>", NSStringFromClass(self.class), self, (unsigned long)self.sequence, self.impulse];
}

- (NSString *)debugLine {
    return [NSString stringWithFormat:@"Event: (%lu), %@", (unsigned long)_sequence, _impulse];
}

@end


@implementation BGResource
@dynamic traced;
@dynamic valuePersistence;

- (instancetype)initWithExtent:(BGExtent *)extent {
    return [self initWithExtent:extent value:nil event:nil];
}

- (instancetype)initWithExtent:(BGExtent *)extent value:(id)value event:(BGEvent *)event {
    self = [super init];
    _subsequents = [NSHashTable weakObjectsHashTable];
    _value = value;
    _event = event;
    [extent addResource:self];
    return self;
}

- (BOOL)justUpdated {
    return [self justUpdated:nil useTo:NO from:nil useFrom:NO];
}

- (BOOL)justUpdatedTo:(id _Nullable)toValue {
    return [self justUpdated:toValue useTo:YES from:nil useFrom:NO];
}

- (BOOL)justUpdatedToSomething {
    return self.justUpdated && self.value != nil;
}

- (BOOL)hasUpdated {
    return _graph && _event && _event != BGUnknownPast;
}

- (BOOL)traceHasUpdated {
    BGEvent *traceEvent;
    return _graph && (traceEvent = self.traceEvent) && traceEvent != BGUnknownPast;
}

- (BOOL)hasUpdatedSince:(BGResource *)since {
    return self.event && self.event.sequence >= since.event.sequence;
}

- (id)traceValue {
    return self.traced && _event == _graph.currentEvent ? _previousValue : _value;
}

- (BGEvent *)traceEvent {
    return self.traced && _event == _graph.currentEvent ? _previousEvent : _event;
}

- (BOOL)justUpdated:(id)toValue useTo:(BOOL)useTo from:(id _Nullable)fromValue useFrom:(BOOL)useFrom {
    if (_graph.currentEvent == nil || self.event != _graph.currentEvent) {
        return NO;
    }
    if (useTo && !bg_equal(self.value, toValue)) {
        return NO;
    }
    if (useFrom && !bg_equal(self.traceValue, fromValue)) {
        return NO;
    }
    return YES;
}

- (void)notifySubsequents {
    for (BGBehavior *subsequent in _subsequents) {
        [_graph submitToQueue:subsequent];
    }
}

- (BOOL)assertUpdateable {
    NSAssert(_extent.addedToGraph, @"A resource can only be updated after its been added to a graph.");
    NSAssert(_graph.currentEvent, @"A resources's value can only be updated during an event loop.");
    NSAssert(_behavior ? _behavior == _graph.currentBehavior : YES, @"A resource's value can only be updated while its behavior is responding.");
    NSAssert(!_behavior ? _graph.currentBehavior == nil : YES, @"A non supplied resource can only be updated at the start of a new event loop inside a submitChanges block.");
    return YES;
}

- (void)_updateValue:(id)value {
    NSAssert([self assertUpdateable], @"Cannot update");
    if (!bg_equal(_value, value)) {
        [self _forceUpdateValue:value];
    }
}

- (void)_forceUpdateValue:(id)value {
    NSAssert([self assertUpdateable], @"Cannot update");

    if (self.traced) {
        if (_previousEvent.sequence < self.graph.sequence) {
            _previousValue = _value;
            _previousEvent = _event;
        }
    } else {
        if (_value) {
            [self.graph.deferredRelease addObject:_value];
        }
        _previousValue = nil;
        _previousEvent = nil;
    }
    
    
    _value = value;
    _event = _graph.currentEvent;
    [self notifySubsequents];
    [self logUpdate];
    
    if (self.valuePersistence != BGResourcePersistent) {
        [_graph trackTransient:self];
    }        
}

- (void)clearTransient {
    switch (self.valuePersistence) {
        case BGResourceTransient:
            if (_value) {
                [self.graph.deferredRelease addObject:_value];
            }
            _value = nil;
            break;
        case BGResourceTransientTrace:
            if (_previousValue) {
                [self.graph.deferredRelease addObject:_previousValue];
            }
            _previousValue = nil;
            break;
        case BGResourcePersistent:
            break;
    }
}

- (void)logUpdate {
    if (@available(ios 12, *)) {
        os_signpost_id_t eventSid = os_signpost_id_generate(_graph.splog);
        os_signpost_event_emit(_graph.splog, eventSid, "resource updated", "name=\"%@\" value=\"%@\"", self.staticDebugName, self.value);
    }
    os_log_debug(_graph.aclog, " - %@ => %@  (%@(%p))", _staticDebugName, _value, NSStringFromClass([_extent class]), _extent);
}

- (NSString *)description {
    return [self debugDescription];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@:%p (%@) value=%@>", NSStringFromClass(self.class), self, self.staticDebugName, _value];
}

- (NSString *)debugLine {
    return [NSString stringWithFormat:@"  %@ (%lu): %@", self.staticDebugName, (unsigned long)_event.sequence, _value];
}

@end

@implementation BGMoment

- (void)update {
    [self _forceUpdateValue:nil];
}

- (void)updateValue:(id)value {
    [self _forceUpdateValue:value];
}

- (void)logUpdate {
    if (@available(ios 12, *)) {
        if (os_signpost_enabled(_graph.splog)) {
            os_signpost_id_t eventSid = os_signpost_id_generate(_graph.splog);
            if (self.value) {
                os_signpost_event_emit(_graph.splog, eventSid, "BGMoment happened", "name=\"%@\" value=\"%@\"", self.staticDebugName, self.value);
            } else {
                os_signpost_event_emit(_graph.splog, eventSid, "BGMoment happened", "name=\"%@\"", self.staticDebugName);
            }
        }
    }
    os_log_debug(_graph.aclog, " - %@ => %@  (%@(%p))", _staticDebugName, self.value, NSStringFromClass([_extent class]), _extent);
}

- (BOOL)traced {
    return NO;
}

- (BGResourceValuePersistence)valuePersistence {
    return BGResourceTransient;
}

@end

@implementation BGState
@synthesize valuePersistence = _valuePersistence;

- (instancetype)initWithExtent:(BGExtent *)extent {
    return [self initWithExtent:(BGExtent *)extent value:nil];
}

- (instancetype)initWithExtent:(BGExtent *)extent value:(id _Nullable)value {
    return [super initWithExtent:extent value:value event:BGUnknownPast];
}

- (BGResourceValuePersistence)valuePersistence {
    return BGResourceTransientTrace;
}

- (BOOL)traced {
    return YES;
}

- (BOOL)justUpdatedFrom:(id _Nullable)fromValue {
    return [self justUpdated:nil useTo:NO from:fromValue useFrom:YES];
}

- (BOOL)justUpdatedTo:(id _Nullable)toValue from:(id _Nullable)fromValue {
    return [self justUpdated:toValue useTo:YES from:fromValue useFrom:YES];
}

- (void)updateValue:(id)value {
    [self _updateValue:value];
}

- (void)updateValueForce:(id)value {
    [self _forceUpdateValue:value];
}

@end


@implementation BGBehavior

- (instancetype _Nonnull)initWithExtent:(BGExtent *)extent
                                demands:(NSArray<BGResource *> * _Nullable)demands
                               supplies:(NSArray<BGResource *> * _Nullable)supplies
                               runBlock:(void (^ _Nullable)(BGExtent * _Nonnull extent))runBlock {
    self = [super init];
    _extent = extent;
    _runBlock = runBlock;
    _demands = [NSHashTable weakObjectsHashTable];
    _supplies = [NSHashTable new];
    [self setDemands:demands];
    [self setSupplies:supplies];
    [extent addBehavior:self];
    return self;
}


- (NSString *)description {
    return [self debugDescription];
}

- (void)setExtent:(BGExtent *)extent {
    _extent = extent;
}

- (NSString *)debugDescription {
    NSString *suppliesString = _supplies.count == 0 ? @"{}" : ({
        NSMutableString *string = [NSMutableString stringWithString:@"{"];
        for (BGResource *supply in _supplies) {
            [string appendFormat:@"\n\t\t%@", supply];
        }
        [string appendString:@"\n}"];
        string;
    });
    return [NSString stringWithFormat:@"<%@:%p (%@) supplies=%@>", NSStringFromClass(self.class), self, self.staticDebugName, suppliesString];
}

- (NSString *)debugLine {
    NSMutableArray *sups = [NSMutableArray new];
    for (BGResource *supply in _supplies) {
        NSString *name = supply.staticDebugName;
        if (name) {
            [sups addObject:name];
        }
    }
    return [NSString stringWithFormat:@"| %@ >", [sups componentsJoinedByString:@","]];
}

- (NSString *)debugCurrentState {
    NSMutableArray *info = [NSMutableArray new];
    [info addObject:[_graph.currentEvent debugLine]];
    [info addObject:@"Demands:"];
    for (BGResource *demand in _demands) {
        [info addObject:[demand debugLine]];
    }
    [info addObject:@"Supplies:"];
    for (BGResource *supply in _supplies) {
        [info addObject:[supply debugLine]];
    }
    return [info componentsJoinedByString:@"\n"];
}

- (void)setDemands:(NSArray<BGResource *> * _Nullable)demands {
    NSAssert(self.extent.addedToGraph == nil || self.graph.processingChanges, @"Demands can only be modified before adding the behavior to the graph or during an event.");
    
    _modifiedDemands = [demands mutableCopy];
    [_graph.modifiedDemands addObject:self];
}

- (void)addDemand:(BGResource * _Nullable)demand {
    NSAssert(self.extent.addedToGraph == nil || self.graph.processingChanges, @"Demands can only be modified before adding the behavior to the graph or during an event.");
    
    if (!demand) {
        // useful instead of having to do the if check everywhere you want to add it
        // although in theory if you meant to add something but were adding nil then you wouldn't be alerted to it
        return;
    }
    
    if (_modifiedDemands) {
        if (![_modifiedDemands containsObject:demand]) {
            [_modifiedDemands addObject:demand];
            [_graph.modifiedDemands addObject:self];
        }
    } else {
        if (![_demands containsObject:demand]) {
            _modifiedDemands = [_demands.allObjects mutableCopy];
            [_modifiedDemands addObject:demand];
            [_graph.modifiedDemands addObject:self];
        }
    }
}

- (void)removeDemand:(BGResource * _Nullable)demand {
    NSAssert(self.extent.addedToGraph == nil || self.graph.processingChanges, @"Demands can only be modified before adding the behavior to the graph or during an event.");
    
    if (!demand) {
        return;
    }
    
    if (_modifiedDemands) {
        if ([_modifiedDemands containsObject:demand]) {
            [_modifiedDemands removeObject:demand];
            [_graph.modifiedDemands addObject:self];
        }
    } else {
        if ([_demands containsObject:demand]) {
            _modifiedDemands = [_demands.allObjects mutableCopy];
            [_modifiedDemands removeObject:demand];
            [_graph.modifiedDemands addObject:self];
        }
    }
}

- (void)setSupplies:(NSArray<BGResource *> * _Nullable)supplies {
    NSAssert(self.extent.addedToGraph == nil || self.graph.processingChanges, @"Supplies can only be modified before adding the behavior to the graph or during an event.");
    
    for (BGResource *supply in _supplies) {
        if (![supplies containsObject:supply]) {
            // Removed supply
            supply.behavior = nil;
        }
    }
    
    for (BGResource *supply in supplies) {
        if (![_supplies containsObject:supply]) {
            // Added supply
            NSAssert(!supply.behavior, @"Supply already added to a different behavior.");
            supply.behavior = self;
            
            for (BGBehavior *subsequent in supply.subsequents) {
                [self.graph.modifiedDemands addObject:subsequent];
            }
        }
    }
    
    [_supplies removeAllObjects];
    for (BGResource *supply in supplies) {
        NSAssert(supply.behavior == self, nil);
        [_supplies addObject:supply];
    }
}

@end

@implementation BGAction

- (instancetype)initWithName:(NSString *)name block:(dispatch_block_t)block {
    self = [super init];
    _name = name;
    _block = block;
    return self;
}

@end

@implementation BGSideEffect

- (instancetype)initWithName:(NSString *)name event:(BGEvent *)event {
    NSAssert(self.class != BGSideEffect.class, @"Abstract");
    return self;
}

- (void)run {
    NSAssert(NO, @"Abstract");
}

- (NSString *)description {
    return self.debugDescription;
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@:%p name=%@ event=%@>", NSStringFromClass(self.class), self, _name, _event];
}

@end

@implementation BGBehaviorSideEffect

- (instancetype)initWithName:(NSString *)name event:(BGEvent *)event extent:(BGExtent *)extent block:(void (^)(BGExtent * _Nullable))block {
    self = [super init];
    _name = name;
    _event = event;
    _extent = extent;
    _block = block;
    return self;
}

- (void)run {
    _block(_extent);
}

@end

@implementation BGGraphSideEffect

- (instancetype)initWithName:(NSString *)name event:(BGEvent *)event block:(dispatch_block_t)block {
    self = [super init];
    _name = name;
    _event = event;
    _block = block;
    return self;
}

- (void)run {
    _block();
}

@end

@implementation BGEventLoopState

- (NSUInteger)sequence {
    return _event.sequence;
}

@end

@implementation BGGraph

+ (void)initialize {
    if (self == BGGraph.class) {
        NullPushedValue = [NSObject new];
    }
}

- (instancetype)init {
    self = [super init];
    
    NSString *subsystem = [NSBundle mainBundle].bundleIdentifier;
    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-signpostBehaviorGraphActivity"]) {
        _splog = os_log_create(subsystem.UTF8String, "bg-signpost");
    } else {
        _splog = OS_LOG_DISABLED;
    }
    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-logBehaviorGraphActivity"]) {
        _aclog = os_log_create(subsystem.UTF8String, "bg-log");
    } else {
        _aclog = OS_LOG_DISABLED;
    }
    if (@available(iOS 12, *)) {
        os_signpost_event_emit(_splog, os_signpost_id_generate(_splog), "graph created", "id=%p", self);
    }
    os_log_debug(_aclog, "graph created: id=%p", self);
    
    _behaviorQueue = [[BGPriorityQueue<BGBehavior *> alloc] initWithComparisonBlock:^CFComparisonResult(BGBehavior * _Nonnull obj1, BGBehavior * _Nonnull obj2) {
        if (obj1.order < obj2.order) {
            return kCFCompareLessThan;
        } else if (obj1.order > obj2.order) {
            return kCFCompareGreaterThan;
        } else {
            return kCFCompareEqualTo;
        }
    }];
    
    _actionQueue = [NSMutableArray new];
    _sideEffectQueue = [NSMutableArray new];
    
    _untrackedBehaviors = [NSMutableSet new];
    _modifiedDemands = [NSMutableSet new];
    _updatedTransientResources = [NSMutableArray new];
    _deferredRelease = [NSMutableArray new];
    _needsOrdering = [NSMutableSet new];
    
    _rootExtent = [[BGExtent alloc] initWithGraph:self];
    _currentEventResource = [_rootExtent stateWithValue:nil];
    _currentEventResource.staticDebugName = @"currentEventResource";
    [self addExtent:_rootExtent event:BGUnknownPast];
    
    return self;
}

- (void)action:(NSString * _Nullable)impulse runBlock:(dispatch_block_t _Nonnull)changes {
    [self action:impulse requireSync:_defaultRequireSync runBlock:changes];
}

- (void)action:(NSString *)impulse requireSync:(BOOL)requireSync runBlock:(dispatch_block_t)changes {
    [self _action:impulse requireSync:requireSync changes:changes];
}

- (void)_action:(NSString *)impulse requireSync:(BOOL)requireSync changes:(dispatch_block_t)changes {
    if (self.processingAction) {
        NSAssert(!requireSync, @"Cannot synchronously complete nested action. Either relax the synchronous requirement for this action or fold changes into current action.");
        requireSync = NO;
    }
    
    NSAssert(!(self.assertOnLeakedSideEffects && self.processingChanges), @"Side effect leaked while processing changes.");
    
    BGAction *action = [[BGAction alloc] initWithName:impulse block:changes];
    [_actionQueue addObject:action];
    
    if (_eventLoopDrivers == 0 || requireSync) {
        [self eventLoop];
    }
}

- (void)eventLoop {
    ++_eventLoopDrivers;
    while (YES) {
        @autoreleasepool {
            if (_eventLoopState.processingChanges) {
                if (_untrackedBehaviors.count > 0) {
                    [self addUntrackedBehaviors];
                }
                
                if (_modifiedDemands.count > 0) {
                    [self commitModifiedDemands];
                }
                
                if (_needsOrdering.count > 0) {
                    [self orderBehaviors];
                }
                
                if (_behaviorQueue.count > 0) {
                    BGBehavior *subsequent = [_behaviorQueue pop];
                    [self runBehavior:subsequent];
                    continue;
                }
            }
            
            _eventLoopState.processingChanges = NO;
            
            if (_sideEffectQueue.count > 0) {
                BGSideEffect *sideEffect = _sideEffectQueue[0];
                [_sideEffectQueue removeObjectAtIndex:0];
                [sideEffect run];
                continue;
            }
            
            if (_updatedTransientResources.count > 0) {
                [self clearUpdatedTransientResources];
                continue;
            }

            if (_deferredRelease.count > 0) {
                // Retaining any objects that might be going to nil until the end of the event loop
                // This limits ways that resource updates and clearing transients might cause
                // deallocs which could potentially force new events during the update phase
                [_deferredRelease removeAllObjects];
                continue;
            }
            
            if (_eventLoopState) {
                NSAssert(!self.processingAction && !self.processingChanges, nil);
                
                BGEventLoopState *eventLoopState = _eventLoopState;
                _eventLoopState = nil;
                
                if (@available(ios 12, *)) {
                    os_signpost_interval_end(_splog, eventLoopState.eventSid, "event loop");
                }
            }
            
            if (_actionQueue.count > 0) {
                NSDate *timestamp = [_dateProvider bg_currentDate] ?: [NSDate date];
                
                BGAction *action = _actionQueue[0];
                [_actionQueue removeObjectAtIndex:0];
                
                BGEvent *event = [[BGEvent alloc] initWithImpulse:action.name sequence:(_lastEvent.sequence + 1) timestamp:timestamp];
                _lastEvent = event;
                
                _eventLoopState = [BGEventLoopState new];
                _eventLoopState.event = event;
                _eventLoopState.processingAction = YES;
                _eventLoopState.processingChanges = YES;
                
                if (@available(ios 12, *)) {
                    _eventLoopState.eventSid = os_signpost_id_generate(_splog);
                    os_signpost_interval_begin(_splog, _eventLoopState.eventSid, "event loop", "impulse=\"%@\" sequence=%lu timestamp=\"%@\"", event.impulse, (unsigned long)event.sequence, event.timestamp);
                }
                os_log_debug(_aclog, "=== event %@ sequence=%lu timestamp=%@ ===", event.impulse, (unsigned long)event.sequence, event.timestamp);
                
                action.block();
                [_currentEventResource updateValueForce:event];

                _eventLoopState.processingAction = NO;

                // NOTE: We keep the action block around because it may capture capture and retain some external objects
                // If it were to go away right after running then that might cause a dealloc to be called as it goes out of scope internal
                // to the event loop and thus create a side effect during the update phase.
                // So we keep it around until after all updates are processed.
                [_deferredRelease addObject:action];
                
                continue;
            }
            break;
        }
    }
    --_eventLoopDrivers;
}

- (BGEvent *)currentEvent {
    return _eventLoopState.event;
}

- (BOOL)processingChanges {
    return _eventLoopState.processingChanges;
}

- (BOOL)processingAction {
    return _eventLoopState.processingAction;
}

- (NSUInteger)sequence {
    return _eventLoopState.sequence;
}

- (void)submitToQueue:(BGBehavior *)behavior {
    NSAssert(behavior.lastUpdateSequence != _eventLoopState.sequence, @"Behavior already ran.");
    if (behavior.enqueuedSequence < self.sequence) {
        behavior.enqueuedSequence = self.sequence;
        [_behaviorQueue push:behavior];
    }
}

- (void)runBehavior:(BGBehavior *)behavior {
    // jlou 2/5/19 - This assert checks for graph implementation bugs, not for user error.
    NSAssert(behavior.lastUpdateSequence < self.sequence, @"Behaviors should only run once per cycle.");
    if (behavior.removedSequence != self.sequence) {
        _currentBehavior = behavior;
        behavior.lastUpdateSequence = self.sequence;
        if (behavior.runBlock) {
            unsigned long long behaviorSid = 0;
            if (@available(iOS 12, *)) {
                behaviorSid = os_signpost_id_generate(_splog);
                os_signpost_interval_begin(_splog, behaviorSid, "behavior run begin", "name=\"%@\"", [behavior debugLine]);
            }
            os_log_debug(_aclog, " %@  (%@(%p))", [behavior debugLine], NSStringFromClass([behavior.extent class]), behavior.extent);
            
            behavior.runBlock(behavior.extent);
            if (@available(iOS 12, *)) {
                os_signpost_interval_end(_splog, behaviorSid, "behavior run end");
            }
        }
        _currentBehavior = nil;
    }
}

- (void)sideEffect:(NSString *)name runBlock:(dispatch_block_t)block {
    __auto_type sideEffect = [[BGGraphSideEffect alloc] initWithName:name event:self.currentEvent block:block];
    [self submitSideEffect:sideEffect];
}

- (void)submitSideEffect:(BGSideEffect * _Nonnull)sideEffect {
    NSAssert(self.processingChanges, @"Can only submit an after-changes block during a graph cycle.");
    [_sideEffectQueue addObject:sideEffect];
}

- (void)addUntrackedBehaviors {
    for (BGBehavior *behavior in _untrackedBehaviors) {
        [_modifiedDemands addObject:behavior];
    }
    [_untrackedBehaviors removeAllObjects];
}

- (void)commitModifiedDemands {
    for (BGBehavior *subsequent in _modifiedDemands) {
        NSMutableSet<BGResource *> *addedDemands;
        NSMutableSet<BGResource *> *removedDemands;
        BOOL needsRunning = NO;
        if (subsequent.modifiedDemands) {
            for (BGResource *demand in subsequent.demands) {
                if (![subsequent.modifiedDemands containsObject:demand]) {
                    if (!removedDemands) {
                        removedDemands = [NSMutableSet new];
                    }
                    [removedDemands addObject:demand];
                }
            }
            
            for (BGResource *demand in subsequent.modifiedDemands) {
                NSAssert(demand.graph == self && demand.extent.addedToGraph != nil, @"Added demands must be added to the graph.");
                if (![subsequent.demands containsObject:demand]) {
                    if (!addedDemands) {
                        addedDemands = [NSMutableSet new];
                    }
                    [addedDemands addObject:demand];
                }
            }
            
            for (BGResource *demand in removedDemands) {
                [demand.subsequents removeObject:subsequent];
                [subsequent.demands removeObject:demand];
            }
            
            for (BGResource *demand in addedDemands) {
                [demand.subsequents addObject:subsequent];
                if (demand.justUpdated && (subsequent.lastUpdateSequence != _eventLoopState.sequence)) {
                    // Activate the behavior if it
                    // * now newly demands a resource that has already been updated this event
                    // * has not already run this event (don't try to run twice)
                    needsRunning = YES;
                }
                [subsequent.demands addObject:demand];
            }
        }
            
        BOOL needsOrdering = (subsequent.orderingState == BGOrderingStateUnordered);
        if (!needsOrdering) {
            for (BGResource *demand in subsequent.demands) {
                BGBehavior *orderedPrior = (BGBehavior *)demand.behavior;
                if (orderedPrior.orderingState == BGOrderingStateOrdered && orderedPrior.order >= subsequent.order) {
                    needsOrdering = YES;
                }
            }
        }
        
        if (needsOrdering) {
            [_needsOrdering addObject:subsequent];
        }

        if (needsRunning) {
            [self submitToQueue:subsequent];
        }
        

        subsequent.modifiedDemands = nil;
    }
    
    [_modifiedDemands removeAllObjects];
}

- (void)orderBehaviors {
    __auto_type needsOrdering = [NSMutableArray<BGBehavior *> new];
    
    // Walk subsequents and add to needs ordering list
    {
        __auto_type traversalQueue = [NSMutableArray<BGBehavior *> new];
        
        // Add unsorted behaviors to traversal queue and temporarily mark each as 'ordered'
        // so that it will be traversed when first encountered.
        for (BGBehavior *behavior in _needsOrdering) {
            behavior.orderingState = BGOrderingStateOrdered;
            [traversalQueue addObject:behavior];
        }
        [_needsOrdering removeAllObjects];
        
        while (traversalQueue.count > 0) {
            BGBehavior *behavior = traversalQueue[0];
            [traversalQueue removeObjectAtIndex:0];
            
            if (behavior.orderingState != BGOrderingStateUnordered) {
                behavior.orderingState = BGOrderingStateUnordered;
                
                [needsOrdering addObject:behavior];
                
                for (BGResource *supply in behavior.supplies) {
                    for (BGBehavior *subsequent in supply.subsequents) {
                        [traversalQueue addObject:subsequent];
                    }
                }
            }
        }
    }
    
    BOOL needsReheap = NO;
    for (BGBehavior *behavior in needsOrdering) {
        [self sortDFS:behavior needsReheap:&needsReheap];
    }
    
    if (needsReheap) {
        [_behaviorQueue needsResort];
    }
}

- (void)clearUpdatedTransientResources {
    while (_updatedTransientResources.count > 0) {
        BGResource *rez = [_updatedTransientResources  objectAtIndex:0];
        [_updatedTransientResources removeObjectAtIndex:0];
        [rez clearTransient];
    }
}

- (NSString *)cycleStringForBehavior:(BGBehavior *)behavior {
    NSMutableArray<BGResource *> *stack = [NSMutableArray new];
    BOOL found = [self cyclePrinterDFSCurrent:behavior target:behavior resourceStack:stack];
    if (found) {
        NSMutableArray<NSString *> *output = [NSMutableArray new];
        while (stack.count > 0) {
            BGResource *resource = [stack lastObject];
            [stack removeLastObject];
            [output addObject:[NSString stringWithFormat:@"| (%@) %@ >",
                               NSStringFromClass(resource.behavior.extent.class), resource.staticDebugName ?: resource.debugDescription]];
        }
        NSMutableArray<NSString *> *behaviorSupplies = [NSMutableArray new];
        for (BGResource *resource in behavior.supplies) {
            [behaviorSupplies addObject:resource.staticDebugName ?: resource.debugDescription];
        }
        NSString *outputLine = [NSString stringWithFormat:@"| (%@) %@ >",
                                NSStringFromClass(behavior.extent.class), [behaviorSupplies componentsJoinedByString:@","]];
        [output addObject:outputLine];
        return [output componentsJoinedByString:@"\n"];
    } else {
        // no cycle found
        return nil;
    }
}

- (BOOL)cyclePrinterDFSCurrent:(BGBehavior *)currentBehavior target:(BGBehavior *)targetBehavior resourceStack:(NSMutableArray<BGResource *> *)stack {
    for (BGResource *resource in currentBehavior.demands) {
        [stack addObject:resource];
        if (resource.behavior == targetBehavior) {
            return YES; // cycle detected
        }
        if ([self cyclePrinterDFSCurrent:resource.behavior target:targetBehavior resourceStack:stack]) {
            return YES;
        }
        [stack removeLastObject];
    }
    return NO;
}

- (void)sortDFS:(BGBehavior * _Nonnull)behavior needsReheap:(BOOL * _Nonnull)needsReheap {
    NSAssert(behavior.orderingState != BGOrderingStateOrdering, @"Dependency cycle detected:\n%@", [self cycleStringForBehavior:behavior]);
    if (behavior.orderingState == BGOrderingStateUnordered) {
        behavior.orderingState = BGOrderingStateOrdering;
        NSUInteger order = PriorlessOrder + 1;
        for (BGResource *demand in behavior.demands) {
            BGBehavior * orderedPrior = demand.behavior;
            if (orderedPrior.orderingState != BGOrderingStateOrdered) {
                [self sortDFS:orderedPrior needsReheap:needsReheap];
            }
            order = MAX(order, orderedPrior.order + 1);
        }
        behavior.orderingState = BGOrderingStateOrdered;
        if (order != behavior.order) {
            behavior.order = order;
            *needsReheap = YES;
        }
    }
}

- (void)removeResource:(BGResource *)resource {
 
    // any foreign behaviors that demand this resource should have
    // it removed as a demand
    BOOL removed = NO;
    for (BGBehavior *subsequent in resource.subsequents) {
        if (subsequent.extent != resource.extent) {
            [subsequent.demands removeObject:resource];
            removed = YES;
        }
    }

    // and clear out all subsequents since its faster than removing
    // them one at a time
    if (removed) {
        [resource.subsequents removeAllObjects];
    }


    // any foreign behaviors that supply this resource should have
    // it removed as a supply
    if (resource.behavior.extent != resource.extent) {
        [resource.behavior.supplies removeObject:resource];
        resource.behavior = nil;
    }
}

- (void)removeBehavior:(BGBehavior *)behavior {
    // If we demand a foreign resource then we should be
    // removed from its list of subsequents
    BOOL removed = NO;
    for (BGResource *demand in behavior.demands) {
        if (demand.extent != behavior.extent) {
            [demand.subsequents removeObject:behavior];
            removed = YES;
        }
    }
    // and remove foreign demands
    // its faster to erase the whole list than pick out the foreign ones
    if (removed) {
        [behavior.demands removeAllObjects];
    }

    // any foreign resources should no longer be supplied by this behavior
    removed = NO;
    for (BGResource *supply in behavior.supplies) {
        if (supply.extent != behavior.extent) {
            supply.behavior = nil;
            removed = YES;
        }
    }
    // and clear out those foreign supplies
    // its faster to clear whole list than pick out individual foreign ones
    if (removed) {
        [behavior.supplies removeAllObjects];
    }

    behavior.removedSequence = self.sequence;
}

- (void)addExtent:(BGExtent *)extent event:(BGEvent *)event {
    NSAssert(extent.addedToGraph == nil, @"Extent cannot be added to the graph twice.");
    extent.addedToGraph = event;
    for (BGBehavior * behavior in extent.allBehaviors.allObjects) {
        [_untrackedBehaviors addObject:behavior];
    }
    // Activate the behavior that updates .added for the extent
    // (If event is BGUnknown past it means we are adding the root
    // behavior so we aren't really running inside an event so
    // we shouldn't try to run the added behavior.)
    if (event != BGUnknownPast) {
        [self submitToQueue:extent.added.behavior];
    }
}

- (void)removeExtent:(BGExtent *)extent {
    NSAssert(self.processingChanges, @"Extents must be removed during an event.");
    NSAssert(extent.addedToGraph != nil, @"Extent cannot be removed from graph twice.");
    for (BGResource *resource in extent.allResources) {
        [self removeResource:resource];
    }
    for (BGBehavior *behavior in extent.allBehaviors) {
        [self removeBehavior:behavior];
    }
    extent.addedToGraph = nil;
}

- (void)trackTransient:(BGResource *)rez {
    [_updatedTransientResources addObject:rez];
}

@end

@interface BGSelector : NSObject
@property (nonatomic) NSString *name;
@property (nonatomic) SEL selector;
@end

@implementation BGSelector
- (NSString *)description {
    return [self debugDescription];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass(self.class), self, _name];
}

- (NSUInteger)hash {
    return [_name hash];
}

- (BOOL)isEqual:(id)object {
    return [_name isEqual:object];
}
@end

@implementation BGDynamicLinks

- (void)demandSwitches:(NSArray<BGResource *> * _Nonnull)switches
             resources:(void(^ _Nullable)(NSMutableArray<BGResource *> * _Nonnull demands, id _Nonnull extent))resources {
    self.demandSwitches = switches;
    self.dynamicDemands = resources;
}

- (void)supplySwitches:(NSArray<BGResource *> * _Nonnull)switches
             resources:(void(^ _Nullable)(NSMutableArray<BGResource *> * _Nonnull demands, id _Nonnull extent))resources {
    self.supplySwitches = switches;
    self.dynamicSupplies = resources;
}

@end

@implementation BGExtent

static char kDemandableSelectorsKey;
static char kNodeableSelectorsKey;


- (NSString *)debugHere {
    return [self.graph.currentBehavior debugCurrentState];
}

- (void)dealloc {
    // @SAL 8/29/2019-- Removing is a bit tricky right now. If the signal to remove is the dealloc of the extent
    // then we need to capture the allBehaviors before starting submitChanges otherwise it goes away
    // with extent and then we can't access them.
    // Possibly dealloc shouldn't be the signal (but it might be error prone to not use it). Its hard to model
    // when the dealloc happens and we are specifically trying to keep track of those details.
    
    NSSet<BGBehavior *> *allBehaviors = self->_allBehaviors; // save pointer so it won't disappear on us
    BGGraph *graph = self.graph;
    [self.graph action:@"BGExtent dealloc" requireSync:NO runBlock:^{
        for (BGBehavior * behavior in allBehaviors) {
            [graph removeBehavior:behavior];
        }
    }];
}

- (instancetype _Nonnull)initWithGraph:(BGGraph *)graph {
    if (self = [super init]) {
        _graph = graph;
        _allBehaviors = [NSMutableSet new];
        _allResources = [NSMutableSet new];
        
        _added = [self moment];
        [self behaviorWithDemands:nil supplies:@[_added] runBlock:^(BGExtent * _Nonnull extent) {
            [extent.added update];
        }];
    }
    return self;
}

- (void)addToGraph {
    NSAssert(_graph.eventLoopState.processingChanges, @"Extents must be added to a graph during an event.");
    [self nameComponents];
    [_graph addExtent:self event:_graph.currentEvent];
}

- (void)removeFromGraph {
    // @SAL 8/29/2019-- See dealloc for alternate removal process because of memory complications
    [_graph removeExtent:self];
}

- (void)addBehavior:(BGBehavior *)behavior {
    NSAssert(_addedToGraph == nil, @"Cannot add behavior after extent has been added to graph.");
    NSAssert(behavior.extent == nil || behavior.extent == self, @"Behavior can only belong to one extent");
    behavior.extent = self;
    behavior.graph = self.graph;
    [_allBehaviors addObject:behavior];
}

- (void)addResource:(BGResource *)resource {
    NSAssert(_addedToGraph == nil, @"Cannot add resource after extent has been added to graph.");
    NSAssert(resource.extent == nil || resource.extent == self, @"Resource can only belong to one extent");
    if (resource.extent == nil) {
        resource.extent = self;
        resource.graph = self.graph;
        [_allResources addObject:resource];
    }
        
}

- (BGBehavior * _Nonnull)behaviorWithDemands:(NSArray<BGResource *> * _Nullable)demands
                                    supplies:(NSArray<BGResource *> * _Nullable)supplies
                                    runBlock:(void(^_Nullable)(id _Nonnull extent))runBlock {
    BGBehavior *bhv = [[BGBehavior alloc] initWithExtent:self demands:demands supplies:supplies runBlock:runBlock];
    return bhv;
}

- (BGBehavior * _Nonnull)dynamicBehaviorWithDemands:(NSArray<BGResource *> * _Nullable)staticDemands
                                           supplies:(NSArray<BGResource *> * _Nullable)staticSupplies
                                           dynamics:(void(^ _Nullable)(BGDynamicLinks<id> * _Nonnull dynamics, id _Nonnull extent))dynamicBlock
                                           runBlock:(void(^_Nullable)(id _Nonnull extent))runBlock {
    BGDynamicLinks *dynamics = [BGDynamicLinks new];
    if (dynamicBlock) { dynamicBlock(dynamics, self); }
    BOOL hasDemandSwitches = dynamics.demandSwitches.count != 0;
    BOOL hasSupplySwitches = dynamics.supplySwitches.count != 0;

    // Statics are kept on the side in addition to the supplies/demands
    // If a foreign resource that is in the statics goes away we will retain it in this extra list
    // Its not a huge problem since resources don't retain their extent strongly but technically
    // this is imperfect.
    // @SAL 2/16/2021
    // I tried a NSPointerArray solution but its added complexity with minor gain and the real solution
    // is to prevent foreign resources with independent lifetimes disallowed in static list.
    NSMutableArray *baseStaticDemands = [[NSMutableArray alloc] initWithArray:staticDemands];
    NSMutableArray *baseStaticSupplies = [[NSMutableArray alloc] initWithArray:staticSupplies];

    // create ordering resources to linking behaviors happen before the main behavior
    BGResource *demandOrderingResource;
    if (hasDemandSwitches) {
        demandOrderingResource = [self resource];
        [baseStaticDemands addObject:demandOrderingResource];
    }
    
    BGResource *supplyOrderingResource;
    if (hasSupplySwitches) {
        supplyOrderingResource = [self resource];
        [baseStaticDemands addObject:supplyOrderingResource];
    }

    BGBehavior *bhv = [[BGBehavior alloc] initWithExtent:self demands:baseStaticDemands supplies:baseStaticSupplies runBlock:runBlock];
    
    // Make copies of these blocks to capture in linking behavior closures
    // otherwise we retain the whole dynamicConfig object
    // which would possibly retain extra foreign static resources that want to deallocate
    __auto_type dynamicDemandBlock = dynamics.dynamicDemands;
    __auto_type dynamicSupplyBlock = dynamics.dynamicSupplies;
    
    // Linking behaviors
    if (dynamics.dynamicDemands) {
        [self behaviorWithDemands:dynamics.demandSwitches supplies:(demandOrderingResource ? @[demandOrderingResource] : nil) runBlock:^(id  _Nonnull extent) {
            NSMutableArray *dynamicDemands = [NSMutableArray new];
            if (dynamicDemandBlock) {
                dynamicDemandBlock(dynamicDemands, extent);
            }
            [bhv setDemands:[baseStaticDemands arrayByAddingObjectsFromArray:dynamicDemands]];
        }];
    }

    if (dynamics.dynamicSupplies) {
        [self behaviorWithDemands:dynamics.supplySwitches supplies:@[supplyOrderingResource] runBlock:^(id  _Nonnull extent) {
            NSMutableArray *dynamicSupplies = [NSMutableArray new];
            if (dynamicSupplyBlock) {
                dynamicSupplyBlock(dynamicSupplies, extent);
            }
            [bhv setSupplies:[baseStaticSupplies arrayByAddingObjectsFromArray:dynamicSupplies]];
        }];
    }

    return bhv;
}

- (void)nameComponents {
    
    NSArray *nodeableSelectors = objc_getAssociatedObject([self class], &kNodeableSelectorsKey);
    NSArray *demandableSelectors = objc_getAssociatedObject([self class], &kDemandableSelectorsKey);
    
    for (BGSelector *selector in nodeableSelectors) {
        IMP implementation = [self methodForSelector:selector.selector];
        BGBehavior *(*function)(id, SEL) = (void *)implementation;
        BGBehavior * behavior = function(self, selector.selector);
        NSAssert(behavior, @"Process not initialized (%@)", selector.name);
        if (behavior) {
            if (behavior.staticDebugName == nil) {
                behavior.staticDebugName = selector.name;
            }
        }
    }
    
    for (BGSelector *selector in demandableSelectors) {
        IMP implementation = [self methodForSelector:selector.selector];
        BGResource *(*function)(id, SEL) = (void *)implementation;
        BGResource *resource = function(self, selector.selector);
        NSAssert(resource, @"Resource not initialized (%@)", selector.name);
        if (resource) {
            if (resource.staticDebugName == nil) {
                resource.staticDebugName = selector.name;
            }
        }
    }
}

- (void)sideEffect:(NSString *)name runBlock:(void (^)(id _Nonnull))block {
    __auto_type sideEffect = [[BGBehaviorSideEffect alloc] initWithName:name event:self.graph.currentEvent extent:self block:block];
    [self.graph submitSideEffect:sideEffect];
}

- (void)action:(NSString * _Nullable)impulse requireSync:(BOOL)requireSync runBlock:(dispatch_block_t _Nonnull)changes {
    [_graph action:impulse requireSync:requireSync runBlock:changes];
}

- (BGState * _Nonnull)stateWithValue:(id)value {
    return [[BGState alloc] initWithExtent:self value:value];
}

- (BGMoment * _Nonnull)moment {
    return [[BGMoment alloc] initWithExtent:self];
}

- (BGResource * _Nonnull)resource {
    return [[BGResource alloc] initWithExtent:self];
}


+ (void)initialize {
    
    NSMutableSet<BGSelector *> *demandableSelectors = [NSMutableSet new];
    // this captures in case we have superclass that has the demandables
    // we count on initialize happening from superclass down
    NSMutableSet<BGSelector *> *parentDemandableSelectors = objc_getAssociatedObject([self superclass], &kDemandableSelectorsKey);
    if (parentDemandableSelectors.count > 0) {
        [demandableSelectors addObjectsFromArray:parentDemandableSelectors.allObjects];
    }
    NSMutableSet<BGSelector *> *nodeableSelectors = [NSMutableSet new];
    NSMutableSet<BGSelector *> *parentNodeableSelectors = objc_getAssociatedObject([self superclass], &kNodeableSelectorsKey);
    if (parentNodeableSelectors.count > 0) {
        [nodeableSelectors addObjectsFromArray:parentNodeableSelectors.allObjects];
    }
    
    unsigned int count;
    objc_property_t *properties = class_copyPropertyList(self, &count);
    for (unsigned int i = 0; i < count; i++) {
        objc_property_t property = properties[i];
        
        NSString *typeEncoding = ({
            char *typeEncodingCString = property_copyAttributeValue(property, "T");
            NSString *typeEncoding = [NSString stringWithCString:typeEncodingCString encoding:NSASCIIStringEncoding];
            free(typeEncodingCString);
            typeEncoding;
        });
        if ([typeEncoding hasPrefix:@"@"] && typeEncoding.length > 3) {
            Class cls = NSClassFromString([typeEncoding substringWithRange:NSMakeRange(2, typeEncoding.length - 3)]);
            
            BOOL demandable = [cls isSubclassOfClass:BGResource.class];
            BOOL nodeable = [cls isSubclassOfClass:BGBehavior.class];
            
            if (demandable || nodeable) {
                NSString *getterMethodName = ({
                    NSString *methodName;
                    char *getter = property_copyAttributeValue(property, "G"); // Getter
                    if (getter != NULL) {
                        methodName = [NSString stringWithCString:getter encoding:NSASCIIStringEncoding];
                    } else {
                        methodName = [NSString stringWithCString:property_getName(property) encoding:NSASCIIStringEncoding];
                    }
                    free(getter);
                    methodName;
                });
                
                BGSelector *selector = [BGSelector new];
                selector.name = getterMethodName;
                selector.selector = NSSelectorFromString(selector.name);
                
                if (demandable) {
                    [demandableSelectors addObject:selector];
                }
                if (nodeable) {
                    [nodeableSelectors addObject:selector];
                }
            }
        }
    }
    free(properties);
    
    objc_setAssociatedObject(self, &kNodeableSelectorsKey, nodeableSelectors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kDemandableSelectorsKey, demandableSelectors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
