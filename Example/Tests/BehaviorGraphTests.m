//
//  Copyright Yahoo 2021
//

@import XCTest;
#import "BGGraph.h"
#import "BGGraph+Private.h"
#import "TestOnDealloc.h"

BGState<NSNumber *> *timesNBehavior(BGExtent *extent, NSInteger n, BGState<NSNumber *> *demand) {
    BGState<NSNumber *> *p = [extent stateWithValue:nil];
    p.staticDebugName = [NSString stringWithFormat:@"times %li behavior", (long)n];
    [extent behaviorWithDemands:@[demand, extent.added] supplies:@[p] runBlock:^(BGExtent * _Nonnull extent) {
        [p updateValue:@(demand.value.integerValue * n)];
    }];
    return p;
}

BGState<NSNumber *> *addNBehavior(BGExtent *extent, NSInteger n, BGState<NSNumber *> *demand) {
    BGState<NSNumber *> *p = [extent stateWithValue:nil];
    p.staticDebugName = [NSString stringWithFormat:@"add %li behavior", (long)n];
    [extent behaviorWithDemands:@[demand] supplies:@[p] runBlock:^(BGExtent * _Nonnull extent) {
        [p updateValue:@(demand.value.integerValue + n)];
    }];
    return p;
}

BGState<NSNumber *> *productBehavior(BGExtent *extent, BGState<NSNumber *> *demand1, BGState<NSNumber *> *demand2) {
    BGState<NSNumber *> *p = [extent stateWithValue:nil];
    p.staticDebugName = [NSString stringWithFormat:@"product behavior (%@ x %@)", demand1, demand2];
    [extent behaviorWithDemands:@[demand1, demand2] supplies:@[p] runBlock:^(BGExtent * _Nonnull extent) {
        [p updateValue:@(demand1.value.integerValue * demand2.value.integerValue)];
    }];
    return p;
}


@interface MathBehavior : BGExtent
@property (nonatomic) BGState<NSNumber *> *times2;
@property (nonatomic) BGState<NSNumber *> *add1;
@end

@implementation MathBehavior

- (instancetype)initWithTimes2Resource:(BGState<NSNumber *> *)times2Demand add1Resource:(BGState<NSNumber *> *)add1Demand graph:(BGGraph *)graph {
    if (self = [super initWithGraph:graph]) {
        if (times2Demand) {
            _times2 = timesNBehavior(self, 2, times2Demand);
        }
        
        if (add1Demand) {
            _add1 = addNBehavior(self, 1, add1Demand);
        }
        
    }
    return self;
}

@end

@interface ClassLikeContainer : BGExtent
@property (nonatomic) BGState<NSNumber *> *doubled;
@property (nonatomic) BGState<NSNumber *> *tripled;
@property (nonatomic) BGState<NSNumber *> *summed;
@end

@implementation ClassLikeContainer

- (instancetype)initWithDemand1:(BGState<NSNumber *> *)demand1 demand2:(BGState<NSNumber *> *)demand2 graph:(BGGraph *)graph {
    if (self = [super initWithGraph:graph]) {
        
        __weak typeof(self) weakSelf = self;
        _doubled = [self stateWithValue:nil];
        [self behaviorWithDemands:@[demand1] supplies:@[_doubled] runBlock:^(BGExtent * _Nonnull extent) {
            [weakSelf.doubled updateValue:(demand1.value ? @(demand1.value.integerValue * 2) : nil)];
        }];
        
        _tripled = [self stateWithValue:nil];
        [self behaviorWithDemands:@[demand1] supplies:@[_tripled] runBlock:^(BGExtent * _Nonnull extent) {
            [weakSelf.tripled updateValue:(demand1.value ? @(demand1.value.integerValue * 3) : nil)];
        }];
        
        _summed = [self stateWithValue:nil];
        [self behaviorWithDemands:@[demand1, demand2] supplies:@[_summed] runBlock:^(BGExtent * _Nonnull extent) {
            [weakSelf.summed updateValue:((demand1.value || demand2.value) ? @(demand1.value.integerValue + demand2.value.integerValue) : nil)];
        }];
    }
    return self;
}

@end

@interface BehaviorGraphTests : XCTestCase
@property (nonatomic) BGGraph *graph;
@property (nonatomic) BGState<NSNumber *> *sp1;
@property (nonatomic) BGState<NSNumber *> *sp2;
@property (nonatomic) BGMoment *action;
@property (nonatomic) BGExtent *rootExt;
@property (nonatomic) BGExtent *ext;
@property (nonatomic) BGExtent *setupExt;
@end

@implementation BehaviorGraphTests

- (void)setUp {
    [super setUp];
    
    _graph = [BGGraph new];
    _rootExt = _graph.rootExtent;
    _ext = [[BGExtent alloc] initWithGraph:_graph];
    _setupExt = [[BGExtent alloc] initWithGraph:_graph];
    _sp1 = [_setupExt stateWithValue:nil];
    _sp1.staticDebugName = @"sp1";
    _sp2 = [_setupExt stateWithValue:nil];
    _sp2.staticDebugName = @"sp2";
    _action = [_setupExt moment];
    _action.staticDebugName = @"action";
    [_graph action:@"setUp" runBlock:^{
        [_setupExt addToGraph];
    }];
}

- (void)tearDown {
    _graph = nil;
    _sp1 = nil;
    _sp2 = nil;
    _action = nil;
    _rootExt = nil;
    _ext = nil;
    _setupExt = nil;
    
    [super tearDown];
}

- (void)testStateChange {
    [_graph action:@"a" runBlock:^{
        [_sp1 updateValue:@3];
    }];
    
    XCTAssertEqualObjects(_sp1.value, @3);
    XCTAssertEqualObjects(_sp1.event.impulse, @"a");
}

- (void)testStateOnlySetOnce {
    [_graph action:@"a" runBlock:^{
        [_sp1 updateValue:@3];
    }];
    [_graph action:@"b" runBlock:^{
        [_sp2 updateValue:@4];
    }];

    XCTAssertEqualObjects(_sp1.event.impulse, @"a");
    XCTAssertEqualObjects(_sp2.event.impulse, @"b");
}

- (void)testMultipleStateHaveSameEvent {
    [_graph action:@"a" runBlock:^{
        [_sp1 updateValue:@3];
        [_sp2 updateValue:@4];
    }];
    XCTAssertEqualObjects(_sp1.event, _sp2.event);
}

- (void)testSimpleGraphByHand {
    BGState *supply = [_ext stateWithValue:nil];
    BGBehavior *times2 = [_ext behaviorWithDemands:@[_sp1, _ext.added] supplies:@[supply] runBlock:^(BGExtent * _Nonnull extent) {
        [supply updateValue:@(_sp1.value.integerValue * 2)];
    }];
    times2.staticDebugName = @"times2";
    
    [_graph action:@"add times2" runBlock:^{
        [_ext addToGraph];
    }];
    
    [_graph action:@"run it" runBlock:^{
        [_sp1 updateValue:@3];
    }];
    XCTAssertEqualObjects(supply.value, @6);
}

- (void)testResourceNode {
    __unused BGState *times2 = timesNBehavior(_ext, 2, _sp1);
    
    [_graph action:@"add times2" runBlock:^{
        [_ext addToGraph];
    }];
}

- (void)testMultipleInAndOut {
    BGState<NSNumber *> *minR = [_ext stateWithValue:nil];
    BGState<NSNumber *> *maxR = [_ext stateWithValue:nil];
    [_ext behaviorWithDemands:@[_sp1, _sp2, _ext.added] supplies:@[minR, maxR] runBlock:^(BGExtent * _Nonnull extent) {
        [minR updateValue:@(MIN(_sp1.value.integerValue, _sp2.value.integerValue))];
        [maxR updateValue:@(MAX(_sp1.value.integerValue, _sp2.value.integerValue))];
    }];
    
    [_graph action:@"setup" runBlock:^{
        [_ext addToGraph];
    }];
    
    [_graph action:@"sp1 submit" runBlock:^{
        [_sp1 updateValue:@3];
    }];
    [_graph action:@"sp2 submit" runBlock:^{
        [_sp2 updateValue:@4];
    }];
    
    XCTAssertEqualObjects(minR.value, @3);
    XCTAssertEqualObjects(minR.event, _sp2.event);
    
    XCTAssertEqualObjects(maxR.value, @4);
    XCTAssertEqualObjects(maxR.event, _sp2.event);
}

- (void)testChildBehaviorsIn {
    BGState *times2 = timesNBehavior(_ext, 2, _sp1);

    [_graph action:@"setup" runBlock:^{
        [_ext addToGraph];
    }];
    
    [_graph action:@"sp1" runBlock:^{
        [_sp1 updateValue:@3];
    }];
    XCTAssertEqualObjects(times2.value, @6);
}

- (void)testSimpleOrdering {
    BGState *one = timesNBehavior(_ext, 2, _sp1);
    BGState *two = addNBehavior(_ext, 1, one);
    BGState *three = timesNBehavior(_ext, 3, two);

    [_graph action:@"setup" runBlock:^{
        [_ext addToGraph];
        [_sp1 updateValue:@5];
    }];
    
    XCTAssertEqualObjects(one.value, @10);
    XCTAssertEqualObjects(two.value, @11);
    XCTAssertEqualObjects(three.value, @33);
}

- (void)testUpdateGraphDuringRun {
    __auto_type times2 = timesNBehavior(_ext, 2, _sp1);
    
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    [ext2 behaviorWithDemands:@[_action] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        if (_action.justUpdated) {
            [_ext addToGraph];
        }
    }];
    
    [_graph action:@"setup" runBlock:^{
        [ext2 addToGraph];
        
        [_sp1 updateValue:@2];
    }];
    
    [_graph action:@"action" runBlock:^{
        [_action update];
    }];
    XCTAssertEqualObjects(times2.value, @4);
}

- (void)testAlreadyActivatedBehaviorGetsResortedWhenDependenciesChange {
    __block NSInteger sequencing = 0;
    __block NSInteger ARan = 0;
    __block NSInteger BRan = 0;

    BGResource *reordering = [_ext resource]; // used just for correct ordering of behaviors

    BGResource *Ares = [_ext resource];
    BGBehavior *Abhv = [_ext behaviorWithDemands:@[_sp1, reordering, _ext.added] supplies:@[Ares] runBlock:^(BGExtent * _Nonnull extent) {
        ARan = sequencing;
        sequencing++;
    }];

    BGResource *Bres = [_ext resource];
    BGBehavior *Bbhv = [_ext behaviorWithDemands:@[_sp1, Ares, reordering, _ext.added] supplies:@[Bres] runBlock:^(BGExtent * _Nonnull extent) {
        BRan = sequencing;
        sequencing++;
    }];
    
    // given we have some behaviors where B depends on A
    [_ext behaviorWithDemands:@[_sp1, _ext.added] supplies:@[reordering] runBlock:^(BGExtent * _Nonnull extent) {
        if (_sp1.justUpdated) {
            // swap ordering
            [Abhv setDemands:@[_sp1, reordering, Bres]];
            [Bbhv setDemands:@[_sp1, reordering]];
        }
    }];

    
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    

    // when something happens that inverts the order after both have been activated
    // _sp1 activates both A and B as well as trigger the rewiring behavior to invert
    // their dependency
    [_graph action:@"update add" runBlock:^{
        [_sp1 updateValue:@2];
    }];
    
    // then they should both run but in the new correct order
    XCTAssertNotEqual(ARan, 0);
    XCTAssertNotEqual(BRan, 0);
    XCTAssertGreaterThan(ARan, BRan);
}

- (void)testAlreadyActivatedThenRemovedIsNotRun {
    // @sal 6/4/2019-- Its not 100% clear that this should be true, but
    // we are making it so to be strict. If it turns out to be annoying
    // you should feel free to revisit this.
    

    // given we have a behavior that should be activated by _sp1
    __block BOOL didRun = NO;
    
    BGResource *reordering = [_ext resource];
    
    __unused BGBehavior *Abhv = [_ext behaviorWithDemands:@[_sp1, reordering] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        didRun = YES;
    }];
    
    [_ext behaviorWithDemands:@[_sp1] supplies:@[reordering] runBlock:^(BGExtent * _Nonnull extent) {
        if (_sp1.justUpdated) {
            [_ext removeFromGraph];
        }
    }];
    
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // when something happens that both activates A and triggers the removal
    didRun = NO;
    [_graph action:@"update" runBlock:^{
        [_sp1 updateValue:@2];
    }];
    
    // then A should not run
    XCTAssertFalse(didRun);
}


- (void)testClassStyleContainer {
    __auto_type newExtent = [[ClassLikeContainer alloc] initWithDemand1:_sp1 demand2:_sp2 graph:_graph];
    
    [_graph action:@"setup" runBlock:^{
        [newExtent addToGraph];
    }];
    
    [_graph action:@"sp1" runBlock:^{
        [_sp1 updateValue:@2];
    }];
    XCTAssertEqualObjects(newExtent.doubled.value, @4);
    XCTAssertEqualObjects(newExtent.tripled.value, @6);
    XCTAssertEqualObjects(newExtent.summed.value, @2);
    
    [_graph action:@"sp2" runBlock:^{
        [_sp2 updateValue:@3];
    }];
    XCTAssertEqualObjects(newExtent.summed.value, @5);
}

- (void)testResourcesFilterOutEqualElementsByDefault {
    [_graph action:@"first" runBlock:^{
        [_sp1 updateValue:@1];
    }];
    BGEvent *event = _sp1.event;
    [_graph action:@"second" runBlock:^{
        [_sp1 updateValue:@1];
    }];
    XCTAssertEqual(_sp1.event, event);
}

- (void)testEqualityFilterIsOverridable {
    __weak typeof(self) weakSelf = self;
    BGState *single = [_ext stateWithValue:nil];
    [_ext behaviorWithDemands:@[_sp1, _sp2] supplies:@[single] runBlock:^(BGExtent * _Nonnull extent) {
        // two values come in just set the most recent
        if (weakSelf.sp1.event == weakSelf.graph.currentEvent) {
            [single updateValueForce:weakSelf.sp1.value];
        } else if (weakSelf.sp2.event == weakSelf.graph.currentEvent) {
            [single updateValueForce:weakSelf.sp2.value];
        }
    }];
    
    [_graph action:@"setup" runBlock:^{
        [_ext addToGraph];
    }];
    
    [_graph action:@"sp1" runBlock:^{
        [_sp1 updateValue:@2];
    }];
    [_graph action:@"2" runBlock:^{
        [_sp2 updateValue:@2];
    }];
    
    XCTAssertEqualObjects(single.event, _sp2.event);
}

- (void)testBehaviorsRunWhenAdded {

    // given an already updated resource
    [_graph action:@"sp1" runBlock:^{
        [_sp1 updateValue:@1];
    }];

    // when new behaviors that demands it gets added
    __auto_type *r = timesNBehavior(_ext, 2, _sp1);
    
    [_graph action:@"add behaviors" runBlock:^{
        [_ext addToGraph];
    }];
    
    // then it will be run using that new value
    XCTAssertEqualObjects(r.value, @2);
}

- (void)testRootExtentAddedInPast {
    // |> When we create a new graph
    BGGraph *graph = [BGGraph new];
    
    // |> Then root extent and currentEventResource are initialized as the past
    XCTAssertEqual(graph.rootExtent.addedToGraph, BGEvent.unknownPast);
    XCTAssertEqual(graph.currentEventResource.value, nil);
    XCTAssertEqual(graph.currentEventResource.event, BGEvent.unknownPast);
}

- (void)testCurrentEventResourceUpdatedEveryEvent {
    BGState<NSNumber *> *cycleCounter = [_ext stateWithValue:@0];
    [_ext behaviorWithDemands:@[_graph.currentEventResource] supplies:@[cycleCounter] runBlock:^(BGExtent * _Nonnull extent) {
        [cycleCounter updateValue:@(cycleCounter.value.integerValue + 1)];
    }];
    cycleCounter.staticDebugName = @"single";
    
    [_graph action:@"add counter" runBlock:^{
        [_ext addToGraph];
    }];
    XCTAssertEqualObjects(cycleCounter.value, @1);
    
    [_graph action:@"sp1" runBlock:^{
        [_sp1 updateValue:@10];
    }];
    XCTAssertEqualObjects(cycleCounter.value, @2);
    
    [_graph action:@"sp2" runBlock:^{
        [_sp2 updateValue:@20];
    }];
    XCTAssertEqualObjects(cycleCounter.value, @3);
}

#pragma mark - Remove Behaviors

- (void)testRemovedBehaviorsAreNotRetained {
    // @SAL 8/29/2019-- I suspect this test should do a better job of capturing some idea that
    // behaviors/resources stick around until their owning extent is removed. I don't believe
    // its testing anything interesting at the moment
    __weak __block BGBehavior *outerContainer;
    @autoreleasepool {
        [_graph action:@"add behaviors" runBlock:^{
            @autoreleasepool {
                BGBehavior *container = [_ext behaviorWithDemands:nil supplies:nil runBlock:nil];
                [_ext addToGraph];
                outerContainer = container;
            }
        }];
  
        // @SAL 8/26/2019: seems like after removing array of subsequent behaviors from graph
        // the graph no longer retains the behaviors at all. I believe that's fine.
        //        XCTAssertNotNil(outerContainer);
        
        [_graph action:@"remove behavior" runBlock:^{
            [_ext removeFromGraph];
        }];
        _ext = nil;
    }
    
    XCTAssertNil(outerContainer);
}

- (void)testRemovedResourcesAreRemovedFromForeignDemands {
    // |> Given we have a resource that is demanded both inside and outside extent
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    BGMoment *m1 = [ext2 moment];
    BGBehavior *extBhv = [_ext behaviorWithDemands:@[m1] supplies:nil runBlock:^(id  _Nonnull extent) {}];
    BGBehavior *ext2Bhv = [ext2 behaviorWithDemands:@[m1] supplies:nil runBlock:^(id  _Nonnull extent) {}];
    [_graph action:@"adding" runBlock:^{
        [_ext addToGraph];
        [ext2 addToGraph];
    }];

    // |> When the extent that owns that resource is removed
    [_graph action:@"remove" runBlock:^{
        [ext2 removeFromGraph];
    }];

    // |> Then it will no longer be demanded by the foreign behavior
    XCTAssertEqual(extBhv.demands.count, 0);
    // but it will be left wired in the local behavior (for performance)
    XCTAssertEqual(ext2Bhv.demands.count, 1);
    // and subsequents are all removed (for performance since its faster to remove all than just foreign)
    XCTAssertEqual(m1.subsequents.count, 0);
}

- (void)testRemovedResourcesAreRemovedFromForeignSupplies {
    // |> Given we have resources that are supplied both inside and outside extent
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    BGMoment *supplied1 = [ext2 moment];
    BGMoment *supplied2 = [ext2 moment];
    BGBehavior *extBhv = [_ext behaviorWithDemands:nil supplies:@[supplied1] runBlock:^(id  _Nonnull extent) {}];
    BGBehavior *ext2Bhv = [ext2 behaviorWithDemands:nil supplies:@[supplied2] runBlock:^(id  _Nonnull extent) {}];
    [_graph action:@"adding" runBlock:^{
        [_ext addToGraph];
        [ext2 addToGraph];
    }];

    // |> When the extent that owns those resources is removed
    [_graph action:@"remove" runBlock:^{
        [ext2 removeFromGraph];
    }];

    // |> Then one will no longer be supplied by the foreign behavior
    XCTAssertEqual(extBhv.supplies.count, 0);
    XCTAssertNil(supplied1.behavior);
    // but it will be left wired in the local behavior (for performance)
    XCTAssertEqual(ext2Bhv.supplies.count, 1);
}

- (void)testRemovedBehaviorsAreRemovedFromForeignSubsequents {
    // |> Given we have a behavior which has foreign and local demands
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    BGMoment *demanded1 = [_ext moment];
    BGMoment *demanded2 = [ext2 moment];
    BGBehavior *ext2Bhv = [ext2 behaviorWithDemands:@[demanded1, demanded2] supplies:nil runBlock:^(id  _Nonnull extent) {}];
    [_graph action:@"adding" runBlock:^{
        [_ext addToGraph];
        [ext2 addToGraph];
    }];

    // |> When its owning extent is removed
    [_graph action:@"remove" runBlock:^{
        [ext2 removeFromGraph];
    }];

    // |> Then the foreign demand will have this behavior removed as a subsequent
    XCTAssertEqual(demanded1.subsequents.count, 0);
    // But the local demand won't remove it (for performance)
    XCTAssertEqual(demanded2.subsequents.count, 1);
    // |> And all demands will be removed
    XCTAssertEqual(ext2Bhv.demands.count, 0);
}

- (void)testRemovedBehaviorsAreRemovedAsForeignSuppliers {
    // |> Given we have a behavior which supplies both foreign and local resources
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    BGMoment *supplied1 = [_ext moment];
    BGMoment *supplied2 = [ext2 moment];
    BGBehavior *ext2Bhv = [ext2 behaviorWithDemands:nil supplies:@[supplied1, supplied2] runBlock:^(id  _Nonnull extent) {}];
    [_graph action:@"adding" runBlock:^{
        [_ext addToGraph];
        [ext2 addToGraph];
    }];

    // |> When its owning extent is removed
    [_graph action:@"remove" runBlock:^{
        [ext2 removeFromGraph];
    }];

    // |> Then the foreign supply will have this behavior removed as a supplied by
    XCTAssertNil(supplied1.behavior);
    // |> But the local supply won't remove it
    XCTAssertNotNil(supplied2.behavior);
    // |> And all supplies will be removed from behavior
    XCTAssertEqual(ext2Bhv.supplies.count, 0);
}

#pragma mark - Set Demands

- (void)testAddingDemandLinksBehaviorAsSubsequent {
    BGState<NSNumber *> *runCount = [_ext stateWithValue:@0];
    BGBehavior *runCountProc = [_ext behaviorWithDemands:@[_ext.added] supplies:@[runCount] runBlock:^(BGExtent * _Nonnull extent) {
        [runCount updateValue:@(runCount.value.integerValue + 1)];
    }];
    
    [_graph action:@"add behavior" runBlock:^{
        [_ext addToGraph];
    }];

    [_graph action:@"action 1" runBlock:^{
        [_action update];
        [_graph sideEffect:nil runBlock:^{
            XCTAssertFalse(runCount.justUpdated);
        }];
    }];
    
    [_graph action:@"change demands" runBlock:^{
        [_action update];
        [runCountProc setDemands:@[_action]];
    }];
    
    [_graph action:@"action" runBlock:^{
        [_action update];
        [_graph sideEffect:nil runBlock:^{
            XCTAssertTrue(runCount.justUpdated);
        }];
    }];
}

- (void)testAddingBehaviorThatDemandsAlreadyUpdatedResourceShouldActivateBehavior {
    // NOTE: new behaviors should run if they demand a resource that has already updated in the same event
    
    // |> Given we update a resource
    BGMoment *r1 = [_ext moment];
    __block BOOL b2Run = NO;
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    [_ext behaviorWithDemands:@[r1] supplies:nil runBlock:^(id  _Nonnull extent) {
        [ext2 addToGraph];
    }];
    [_graph action:nil runBlock:^{
        [_ext addToGraph];
    }];
    
    [ext2 behaviorWithDemands:@[r1] supplies:nil runBlock:^(id  _Nonnull extent) {
        b2Run = YES;
    }];
    
    // |> When we add a new extent whith a behavior that demands that resource
    [_graph action:nil runBlock:^{
        [r1 update];
    }];
    
    // |> It should run
    XCTAssertTrue(b2Run);
}

- (void)testUpdatingBehaviorToDemandAlreadyUpdatedResourceShouldActivateBehavior {
    // NOTE: changing a behavior to demand an already updated resource should cause that behavior to run that event

    // |> Given we update a resource
    BGMoment *r1 = [_ext moment];
    __block BOOL b2Run = NO;
    __block BGBehavior *b2;
    [_ext behaviorWithDemands:@[r1] supplies:nil runBlock:^(id  _Nonnull extent) {
        [b2 setDemands:@[r1]];
    }];
    b2 = [_ext behaviorWithDemands:@[] supplies:nil runBlock:^(id  _Nonnull extent) {
        b2Run = YES;
    }];
    [_graph action:nil runBlock:^{
        [_ext addToGraph];
    }];
    
    // |> When we update that behavior to demand the resource in the same event
    [_graph action:nil runBlock:^{
        [r1 update];
    }];
    
    // |> It should run
    XCTAssertTrue(b2Run);

}

- (void)testUpdatingAlreadyRunBehaviorToDemandAlreadyUpdatedResourceShouldntTryToActivateBehavior {
    // NOTE: if a behavior changes to demand a reource that was already updated but that behavior has already run
    // then it shouldn't try to run again (which would be an error)
    
    // |> Given we have two resources (one to activate and one to add later)
    BGMoment *r1 = [_ext moment];
    r1.staticDebugName = @"r1";
    BGMoment *r2 = [_ext moment];
    r2.staticDebugName = @"r2";
    BGMoment *r3 = [_ext moment];
    r3.staticDebugName = @"r3";
    __block BGBehavior *b1;
    b1 = [_ext behaviorWithDemands:@[r1] supplies:@[r2] runBlock:^(id  _Nonnull extent) {
        [r2 update];
    }];
    
    // |> When a behavior that has already run gets that resource added as a demand
    [_ext behaviorWithDemands:@[r2] supplies:nil runBlock:^(id  _Nonnull extent) {
        [b1 setDemands:@[r3]];
    }];
    
    // |> There is no error
    [_graph action:nil runBlock:^{
        [_ext addToGraph];
        [r1 update];
        [r3 update];
    }];
    XCTAssert(YES);
}

- (void)testAddDemandsLaterToBehaviorThatHasntBeenAddedYet {
    // NOTE: When using behavior graph it isn't always easy (or possible)
    // to know the demands in the same code location where the behavior is defined.
    // This confirms we can update demands before attaching that behavior
    // to a graph.
    
    // given a disconnected behavior (ie no demands yet)
    BGState *r = [_ext stateWithValue:nil];
    BGBehavior *p = [_ext behaviorWithDemands:nil supplies:@[r] runBlock:^(BGExtent * _Nonnull extent) {
        [r updateValue:self->_sp1.value];
    }];

    // that is then subsequently linked and added
    [p setDemands:@[_sp1]];
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];

    // when the demanded resource is updated
    [_graph action:@"value" runBlock:^{
        [_sp1 updateValue:@1];
    }];
    
    // then behavior also runs
    XCTAssertEqualObjects(r.value, @1);
}

- (void)testChangingSuppliedResources {
    // setup 3 pass through resources and one behavior that can push values through to the supplied resources
    BGState<NSNumber *> *out1resource = [_ext stateWithValue:nil];
    BGState<NSNumber *> *out1effect = [_ext stateWithValue:nil];
    BGState<NSNumber *> *out2resource = [_ext stateWithValue:nil];
    BGState<NSNumber *> *out2effect = [_ext stateWithValue:nil];
    BGState<NSNumber *> *out3resource = [_ext stateWithValue:nil];
    BGState<NSNumber *> *out3effect = [_ext stateWithValue:nil];

    [_ext behaviorWithDemands:@[out1resource] supplies:@[out1effect] runBlock:^(BGExtent * _Nonnull extent) {
        [out1effect updateValue:out1resource.value];
    }];
    [_ext behaviorWithDemands:@[out2resource] supplies:@[out2effect] runBlock:^(BGExtent * _Nonnull extent) {
        [out2effect updateValue:out2resource.value];
    }];
    BGBehavior *out3bhv = [_ext behaviorWithDemands:nil supplies:@[out3effect] runBlock:^(BGExtent * _Nonnull extent) {
        [out3effect updateValue:out3resource.value];
    }];
    // given a behavior with supplies
    NSMutableArray *resourcesToUpdate = [@[out1resource, out2resource] mutableCopy];
    BGBehavior *fanOut = [_ext behaviorWithDemands:@[_sp1] supplies:resourcesToUpdate runBlock:^(BGExtent * _Nonnull extent) {
        for (BGState<NSNumber *> *r in resourcesToUpdate) {
            [r updateValue:_sp1.value];
        }
    }];
    fanOut.staticDebugName = @"fanOut";
    
    // behavior takes a demand and outputs to two resources in an array
    [_graph action:@"setup" runBlock:^{
        [_ext addToGraph];
        [_sp1 updateValue:@1];
    }];
    
    // when those supplies change
    [resourcesToUpdate removeObject:out1resource];
    [resourcesToUpdate addObject:out3resource];
    [_graph action:@"change supplies" runBlock:^{
        [fanOut setSupplies:resourcesToUpdate];
        [out3bhv setDemands:@[out3resource]];
        // [out1bhv setDemands:nil]; @SAL 4/30/2019-- can't currently remove demands but it seems like one should be able to
        [_sp1 updateValue:@2];
    }];
    
    // then the correspoinding subsequents are notified
    XCTAssertEqualObjects(out1effect.value, @1);
    XCTAssertEqualObjects(out2effect.value, @2);
    XCTAssertEqualObjects(out3effect.value, @2);
}

- (void)testSubsequentsOfNewlySuppliedResourcesReordered {
    BGState *r1 = [_ext stateWithValue:nil];
    [_ext behaviorWithDemands:@[_sp1] supplies:@[r1] runBlock:^(BGExtent * _Nonnull extent) {
        
    }];
    
    BGBehavior *b2 = [_ext behaviorWithDemands:@[r1] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
    }];
    
    BGState *r2 = [_ext stateWithValue:nil]; // initially unsupplied resource
    BGBehavior *b3 = [_ext behaviorWithDemands:@[r2] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
    }];
    
    [_graph action:@"initial add" runBlock:^{
        [_ext addToGraph];
    }];
    XCTAssertLessThanOrEqual(b3.order, b2.order);
    
    [_graph action:@"supply s" runBlock:^{
        [b2 setSupplies:@[r2]];
    }];
    XCTAssertGreaterThan(b3.order, b2.order);
}

- (void)testDependingOnUnsuppliedResource {
    // NOTE: During graph building we may want a single behavior to update
    // multiple fan out resources that are already depended on. So depending
    // on a resource that will eventually get connected to a behavior means
    // we can make that connection without coordinating the construction
    // of subsequent behaviors
    
    // given a behavior that depends on a prior-less resource
    BGState<NSNumber *> *inResource = [_ext stateWithValue:nil];
    BGState<NSNumber *> *outResource = [_ext stateWithValue:nil];
    [_ext behaviorWithDemands:@[inResource] supplies:@[outResource] runBlock:^(BGExtent * _Nonnull extent) {
        if (inResource.justUpdated) {
            [outResource updateValue:inResource.value];
        }
    }];

    [_graph action:@"add p" runBlock:^{
        [_ext addToGraph];
    }];
    
    // when a supplier is later added
    BGExtent *ext2 = [[BGExtent alloc] initWithGraph:_graph];
    [ext2 behaviorWithDemands:@[_sp1] supplies:@[inResource] runBlock:^(BGExtent * _Nonnull extent) {
        [inResource updateValue:_sp1.value];
    }];
    
    [_graph action:@"add supplying behavior" runBlock:^{
        [ext2 addToGraph];
    }];
    
    // then we should get updates
    [_graph action:@"values" runBlock:^{
        [_sp1 updateValue:@1];
    }];
    XCTAssertEqualObjects(outResource.value, @1);
}

- (void)testSuppliedResourcesAddedToGraphAutomatically {
    // given we have an extent with a behavior and supplied resource
    BGState<NSNumber *> *r = [_ext stateWithValue:nil];
    [_ext behaviorWithDemands:@[_sp1] supplies:@[r] runBlock:^(BGExtent * _Nonnull extent) {
        
    }];
    
    // when that extent is added to graph
    [_graph action:@"" runBlock:^{
        [_ext addToGraph];
    }];
    
    // then supplied resource is as well
    XCTAssertEqual(r.graph, _graph);
}

- (void)testDynamicBehaviorReflectsStaticAndDynamicDemands {

    // |> Given a dynamic behavior
    __block NSNumber *lastCalled;
    BGMoment<NSNumber*> *staticR = [_ext moment];
    BGMoment<NSNumber*> *dynamicR = [_ext moment];
    BGMoment *switchR = [_ext moment];
    
    BGBehavior *bhv = [_ext dynamicBehaviorWithDemands:@[staticR]
                                              supplies:nil
                                              dynamics:^(BGDynamicLinks * _Nonnull dynamics, id  _Nonnull extent) {
        [dynamics demandSwitches:@[switchR]
                       resources:^(NSMutableArray<BGResource *> * _Nonnull demands, id  _Nonnull extent) {
            if (switchR.justUpdated) {
                [demands addObject:dynamicR];
            }
        }];
    } runBlock:^(id  _Nonnull extent) {
        if (staticR.justUpdated) {
            lastCalled = staticR.value;
        } else if (dynamicR.justUpdated) {
            lastCalled = dynamicR.value;
        }
    }];

    [_graph action:nil runBlock:^{
        [_ext addToGraph];
    }];
    // static activates, dynamic does not
    [_graph action:nil runBlock:^{
        [staticR updateValue:@1];
    }];
    XCTAssertEqual(lastCalled, @1);
    [_graph action:nil runBlock:^{
        [dynamicR updateValue:@2];
    }];
    XCTAssertEqual(lastCalled, @1);

    // |> When it is relinked
    [_graph action:nil runBlock:^{
        [switchR update];
    }];
    
    // |> Then static resource still activates
    [_graph action:nil runBlock:^{
        [staticR updateValue:@3];
    }];
    XCTAssertEqual(lastCalled, @3);

    // |> And new dynamic resource activates
    [_graph action:nil runBlock:^{
        [dynamicR updateValue:@4];
    }];
    XCTAssertEqual(lastCalled, @4);
    
    // |> And ordering resource is a demand
    XCTAssertEqual(bhv.demands.count, 3);

}

- (void)testDynamicBehaviorReflectsStaticAndDynamicSupplies {
    
    // |> Given a dynamic behavior
    BGMoment<NSNumber*> *staticR = [_ext moment];
    BGMoment<NSNumber*> *dynamicR = [_ext moment];
    BGMoment *switchR = [_ext moment];
    
    BGBehavior *bhv = [_ext dynamicBehaviorWithDemands:nil
                                              supplies:@[staticR]
                                              dynamics:^(BGDynamicLinks * _Nonnull dynamics, id  _Nonnull extent) {
        [dynamics supplySwitches:@[switchR] resources:^(NSMutableArray<BGResource *> * _Nonnull supplies, id  _Nonnull extent) {
            if (switchR.justUpdated) {
                [supplies addObject:dynamicR];
            }
        }];
    } runBlock:^(id  _Nonnull extent) {
        
    }];
    
    [_graph action:nil runBlock:^{
        [_ext addToGraph];
    }];
    // static in supplies, dynamic is not
    XCTAssertTrue([bhv.supplies containsObject:staticR]);
    XCTAssertFalse([bhv.supplies containsObject:dynamicR]);
    
    // |> When it is relinked
    [_graph action:nil runBlock:^{
        [switchR update];
    }];
    
    // |> Then both are supplied
    XCTAssertTrue([bhv.supplies containsObject:staticR]);
    XCTAssertTrue([bhv.supplies containsObject:dynamicR]);

    // |> And ordering resource for supply relinking is a demand
    XCTAssertEqual(bhv.demands.count, 1);

}

- (void)testDynamicBehaviorCreationDoesntRetainStaticsSeparately {
    // NOTE: Shouldn't have foreign links as statics so if that is ever
    // restricted then this test and feature can be removed
    
    // |> Given a dynamic behavior with static foreign supplies and demands
    
    // |> When
}



#pragma mark - Resource Storage Configurations

- (void)testPersistentResourcesPersistCurrentValueAfterCycleCompletes {
    BGState<NSNumber *> *measure = [_ext stateWithValue:nil];
    
    [_graph action:@"1" runBlock:^{
        [_ext addToGraph];
        [measure updateValue:@1];
    }];
    XCTAssertEqualObjects(measure.value, @1);
}

- (void)testTransientResourcesPersistCurrentValueOnlyUntilCycleCompletesButKeepsEvent {
    __block NSNumber *transientValue;
    BGMoment<NSNumber *> *measure = [_ext moment];
    
    __weak typeof(measure) weakMeasure = measure;
    [_ext behaviorWithDemands:@[measure] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        transientValue = weakMeasure.value;
    }];
    
    [_graph action:@"1" runBlock:^{
        [_ext addToGraph];
        [measure updateValue:@1];
    }];
    XCTAssertEqualObjects(transientValue, @1);
    XCTAssertNil(measure.value);
    XCTAssertEqualObjects(measure.event, _graph.lastEvent);
}

- (void)testTransientTracedResourcesPersistPreviousValueOnlyUntilCycleCompletes {
    BGState<NSNumber *> *s1 = [_ext stateWithValue:@0];
    
    [_graph action:@"1" runBlock:^{
        [_ext addToGraph];
        [s1 updateValue:@1];
        [_graph sideEffect:nil runBlock:^{
            XCTAssertEqualObjects(s1.traceValue, @0);
            XCTAssertEqualObjects(s1.traceEvent, BGEvent.unknownPast);
        }];
    }];
    XCTAssertEqual(s1.traceValue, @1);
    XCTAssertEqual(s1.traceEvent, _graph.lastEvent);
}


- (void)testMeasureInitialValues {
    BGState<NSNumber *> *measure = [_ext stateWithValue:@10];
    XCTAssertEqualObjects(measure.value, @10);
    XCTAssertEqual(measure.event.sequence, 0);
    
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    XCTAssertEqualObjects(measure.value, @10);
    XCTAssertEqual(measure.event.sequence, 0);
}

#pragma mark State Resource

- (void)testStateInitialState {
    // • When we create a new State Resource
    BGState<NSNumber *> *state = [_ext stateWithValue:@1];
    
    // • Then it has an initial value
    XCTAssertEqualObjects(state.value, @1);
    XCTAssertEqual(state.event.sequence, 0);
}

- (void)testStateUpdates {
    // • Given a BGState in the graph
    BGState<NSNumber *> *state = [_ext stateWithValue:@1];
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // • When it is updated
    [_graph action:@"update" runBlock:^{
        [state updateValue:@2];
    }];
    
    // • Then it will have that new value with matching event
    XCTAssertEqualObjects(state.value, @2);
    XCTAssertEqual(state.event, _graph.lastEvent);
}

- (void)testStateFiltersForEquality {
    // ◊ Given States in the graph
    BGState<NSNumber *> *state1 = [_ext stateWithValue:@1];
    BGState<NSNumber *> *state2 = [_ext stateWithValue:@1];
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    BGEvent *beforeUpdate = state1.event;
    
    // ◊ When they are updated
    [_graph action:@"update" runBlock:^{
        [state1 updateValue:@1];
        [state2 updateValueForce:@1];
    }];
    
    
    // ◊ forceUpdate goes through, regular update is filtered out due to equality check
    XCTAssertEqual(state1.event, beforeUpdate);
    XCTAssertEqual(state2.event, _graph.lastEvent);
}

- (void)testStateWorksAsResource {
    // <> Given states as resources
    BGState<NSNumber *> *state1 = [_ext stateWithValue:@0];
    BGState<NSNumber *> *state2 = [_ext stateWithValue:@0];
    __block BOOL ran = NO;
    [_ext behaviorWithDemands:@[state1] supplies:@[state2] runBlock:^(BGExtent * _Nonnull extent) {
        if (state1.justUpdated) {
            [state2 updateValue:state1.value];
        }
    }];
    [_ext behaviorWithDemands:@[state2] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        if (state2.justUpdated) {
            ran = YES;
        }
    }];
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // <> When event loop is started
    [_graph action:@"update" runBlock:^{
        [state1 updateValue:@1];
    }];
    
    // <> Then subsequent behavior is run
    XCTAssertEqualObjects(state2.value, @1);
    XCTAssertTrue(ran);
}

- (void)testStateJustChanged {
    // <> Given a state resource
    BGState<NSNumber *> *state1 = [_ext stateWithValue:@0];
    BGState<NSNumber *> *state2 = [_ext stateWithValue:@0];
    __block BOOL changed, notChanged, changedTo, notChangedTo, changedFrom, notChangedFrom, changedToFrom = NO;
    [_ext behaviorWithDemands:@[state1] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        changed = state1.justUpdated;
        notChanged = state2.justUpdated;
        changedTo = [state1 justUpdatedTo:@1];
        notChangedTo = [state1 justUpdatedTo:@2];
        changedFrom = [state1 justUpdatedFrom:@0];
        notChangedFrom = [state1 justUpdatedFrom:@2];
        changedToFrom = [state1 justUpdatedTo:@1 from:@0];
    }];
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // <> When it updates
    [_graph action:@"update" runBlock:^{
        [state1 updateValue:@1];
    }];
    
    // <> Then its justChanged methods behave as expected
    XCTAssertTrue(changed);
    XCTAssertFalse(notChanged);
    XCTAssertTrue(changedTo);
    XCTAssertFalse(notChangedTo);
    XCTAssertTrue(changedFrom);
    XCTAssertFalse(notChangedFrom);
    XCTAssertTrue(changedToFrom);
    // and they don't work outside event loop
    XCTAssertFalse(state1.justUpdated);
}

- (void)testStateCanBeTraced {
    // <> Given a behavior that updates a value
    BGState<NSNumber *> *state1 = [_ext stateWithValue:@0];
    BGState<NSNumber *> *state2 = [_ext stateWithValue:@0];
    
    __block NSNumber *before, *after = nil;
    __block BGEvent *afterEvent = nil;
    
    [_ext behaviorWithDemands:@[state1] supplies:@[state2] runBlock:^(BGExtent * _Nonnull extent) {
        if (state1.justUpdated) {
            before = state2.traceValue;
            [state2 updateValue:@1];
            after = state2.traceValue;
            afterEvent = state2.traceEvent;
        }
    }];
    BGEvent *beforeEvent = state2.event;
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // <> When it updates
    [_graph action:@"update" runBlock:^{
        [state1 updateValue:@1];
    }];

    XCTAssertEqualObjects(before, @0);
    XCTAssertEqualObjects(state2.value, @1);
    XCTAssertEqualObjects(after, @0);
    XCTAssertEqual(beforeEvent, afterEvent);
}

- (void)testTransientPersistenceIsRespected {
    // |> Given transient state resources
    BGMoment<NSNumber *> *moment1 = [_ext moment];
    
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // |> When they are updated
    [_graph action:@"update" runBlock:^{
        [moment1 updateValue:@1];
    }];
    
    // |> Then their values will be updated automatically at the end
    XCTAssertNil(moment1.value);
}

#pragma mark Moment Resource

- (void)testMomentHappens {
    // <> Given a moment in the graph
    BGMoment *moment1 = [_ext moment];
    BGMoment *moment2 = [_ext moment];
    
    __block BOOL before, during, notDuring = NO;
    BOOL after = NO;
    [_ext behaviorWithDemands:@[moment1, moment2] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        during = moment1.justUpdated;
        notDuring = moment2.justUpdated;
    }];

    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];
    
    // <> When it is checked for happened
    before = moment1.justUpdated;
    [_graph action:@"update" runBlock:^{
        [moment1 update];
    }];
    after = moment1.justUpdated;
    
    // <> Then it happened reflects its status in the current event loop
    XCTAssertFalse(before);
    XCTAssertTrue(during);
    XCTAssertFalse(notDuring);
}

- (void)testMomentsCanHaveData {
    // <> Given a moment with data in the graph
    BGMoment<NSNumber *> *moment1 = [_ext moment];
    __block NSNumber *inside = nil;
    
    [_ext behaviorWithDemands:@[moment1] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        if (moment1.justUpdated) {
            inside = moment1.value;
        }
    }];
    [_graph action:@"add" runBlock:^{
        [_ext addToGraph];
    }];

    // <> When it happens
    [_graph action:@"update" runBlock:^{
        [moment1 updateValue:@1];
    }];
    
    // <> Then its data is visible in subsequent behaviors
    XCTAssertEqualObjects(inside, @1);
    
    // But not outside the event loop
    XCTAssertNil(moment1.value);
}

- (void)testCyclesRunSynchronously {
    BGGraph *graph = [BGGraph new];
    BGExtent *ext = [[BGExtent alloc] initWithGraph:graph];
    
    __auto_type r = [[BGState<NSNumber *> alloc] initWithExtent:ext value:nil];
    
    __block NSNumber *capturedValue;
    [ext behaviorWithDemands:@[r] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        if ([r justUpdatedFrom:nil]) {
            [extent sideEffect:nil runBlock:^(BGExtent * _Nonnull extent) {
                // Action submitted from effect requires synchronous running. m2's value should be
                // updated synchronously when this submitChanges call returns and not queued up higher
                // up the stack.
                [extent.graph action:nil requireSync:YES runBlock:^{
                    [r updateValue:@2];
                }];
                
                capturedValue = r.value;
            }];
        }
    }];
    
    [graph action:nil runBlock:^{
        [ext addToGraph];
        
        [r updateValue:@1];
    }];
    
    XCTAssertEqualObjects(capturedValue, @2);
}

- (void)testSynchronousCycleEventExecutionOrder {
    BGGraph *graph = [BGGraph new];
    BGExtent *ext = [[BGExtent alloc] initWithGraph:graph];
    
    __auto_type r = [ext stateWithValue:nil];
    
    __auto_type executionOrder = [NSMutableArray<NSString *> new];
    
    __auto_type orderConstraint = [ext resource];
    [ext behaviorWithDemands:@[r] supplies:@[orderConstraint] runBlock:^(BGExtent * _Nonnull extent) {
        if ([r justUpdatedFrom:nil]) {
            [extent sideEffect:nil runBlock:^(BGExtent * _Nonnull extent) {
                [executionOrder addObject:@"SE_1"];
                [extent.graph action:nil requireSync:YES runBlock:^{
                    [executionOrder addObject:@"EVT_2"];
                    [r updateValue:@2];
                }];
                XCTAssertEqualObjects(r.value, @2); // ran synchronously
            }];
        }
    }];
    
    __auto_type capturedValues = [NSMutableArray<NSNumber *> new];
    [ext behaviorWithDemands:@[r, orderConstraint] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        [extent.graph sideEffect:nil runBlock:^{
            [executionOrder addObject:@"SE_2"];
            [capturedValues addObject:r.value];
        }];
    }];
    
    [graph action:nil runBlock:^{
        [executionOrder addObject:@"EVT_1"];
        [ext addToGraph];
        [r updateValue:@1];
    }];
    
    XCTAssertEqualObjects(capturedValues[0], @1);
    XCTAssertEqualObjects(capturedValues[1], @2);
    
    NSArray<NSString *> *expectedOrder = @[@"EVT_1", @"SE_1", @"SE_2", @"EVT_2", @"SE_2"];
    XCTAssertEqualObjects(executionOrder, expectedOrder);
}

- (void)testAsynchronousCycleEventExecutionOrder {
    BGGraph *graph = [BGGraph new];
    BGExtent *ext = [[BGExtent alloc] initWithGraph:graph];
    
    __auto_type r =  [ext stateWithValue:nil];
    __auto_type executionOrder = [NSMutableArray<NSString *> new];
    
    __auto_type orderConstraint = [ext resource];
    [ext behaviorWithDemands:@[r] supplies:@[orderConstraint] runBlock:^(BGExtent * _Nonnull extent) {
        if ([r justUpdatedFrom:nil]) {
            [extent sideEffect:nil runBlock:^(BGExtent * _Nonnull extent) {
                [executionOrder addObject:@"SE_1"];
                [extent.graph action:nil requireSync:NO runBlock:^{
                    [executionOrder addObject:@"EVT_2"];
                    [r updateValue:@2];
                }];
            }];
            XCTAssertEqualObjects(r.value, @1); // did not synchronously
        }
    }];
    
    __auto_type capturedValues = [NSMutableArray<NSNumber *> new];
    [ext behaviorWithDemands:@[r, orderConstraint] supplies:nil runBlock:^(BGExtent * _Nonnull extent) {
        [extent.graph sideEffect:nil runBlock:^{
            [executionOrder addObject:@"SE_2"];
            [capturedValues addObject:r.value];
        }];
    }];
    
    [graph action:nil runBlock:^{
        [executionOrder addObject:@"EVT_1"];
        [ext addToGraph];
        [r updateValue:@1];
    }];
    
    XCTAssertEqualObjects(r.value, @2);
    
    XCTAssertEqualObjects(capturedValues[0], @1);
    XCTAssertEqualObjects(capturedValues[1], @2);
    
    NSArray<NSString *> *expectedOrder = @[@"EVT_1", @"SE_1", @"SE_2", @"EVT_2", @"SE_2"];
    XCTAssertEqualObjects(executionOrder, expectedOrder);
}

- (void)testPreviousTracedValuesRetainedUntilEndOfEvent {
    BGGraph *graph = [BGGraph new];
    BGExtent *ext = [[BGExtent alloc] initWithGraph:graph];
    
    __block BOOL valDealloced = NO;
    __auto_type r = [ext stateWithValue:[[TestOnDealloc alloc] initWithDeallocBlock:^{
        valDealloced = YES;
    }]];
    
    [graph action:nil requireSync:YES runBlock:^{
        [ext addToGraph];
    }];
    
    [graph action:nil requireSync:YES runBlock:^{
        // Update trace value, original value will no longer retained by resource but will get dealloc'ed later
        [r updateValue:[NSObject new]];
        XCTAssertFalse(valDealloced);
        
        [graph sideEffect:nil runBlock:^{
            XCTAssertFalse(valDealloced);
            
            // Original value should get dealloc'ed by the time the next event is running
            [graph action:nil requireSync:YES runBlock:^{
                XCTAssertTrue(valDealloced);
            }];
        }];
    }];
    XCTAssertTrue(valDealloced);
}

- (void)testMomentsDeferDeallocation {
    // NOTE: We desire to avoid dallocations until after transients have been cleared
    // In order to prevent a new synchronous action from being inserted into the middle
    // of the clearing loop (which could lead to a normal update casing another
    // dealloc based action getting started during the update phase)
    
    // |> Given two moments
    BGMoment<TestOnDealloc *> *moment1 = [_ext moment];
    BGMoment<TestOnDealloc *> *moment2 = [_ext moment];
    [_graph action:@"event 1" runBlock:^{
        [_ext addToGraph];
        // |> When dealloc of first moment happens
        [moment1 updateValue:[[TestOnDealloc alloc] initWithDeallocBlock:^{
            // |> Then other (moment 2) transient resource should have already been cleared
            XCTAssertEqual(_graph.updatedTransientResources.count, 0);
        }]];
        [moment2 updateValue:[[TestOnDealloc alloc] initWithDeallocBlock:^{}]];
    }];

}

- (void)testDeferDeallocsForTransients {
    // NOTE: We want to avoid deallocs during the update phase of the event.
    // Because these can create leaked side effects.
    // This test simulates a nested dealloc that could create this if
    // deallocs aren't deferred until the end.
    
    // - event 1 updates moment 1 and 2 with values
    // - event transient phase clears out moment 1
    // - this creates a dealloc which then starts event 2
    // - event 2 gives a new value to moment 2. If moment 2
    //   hasn't been cleared already then it would create
    //   another leaked side effect
    
    BGMoment<TestOnDealloc *> *moment1 = [_ext moment];
    BGMoment<TestOnDealloc *> *moment2 = [_ext moment];
    [_graph action:@"event 1" runBlock:^{
        [_ext addToGraph];
        [moment1 updateValue:[[TestOnDealloc alloc] initWithDeallocBlock:^{
            [_graph action:@"event 2" requireSync:YES runBlock:^{
                [moment2 updateValue:nil];
            }];
        }]];
        [moment2 updateValue:[[TestOnDealloc alloc] initWithDeallocBlock:^{
            XCTAssertFalse(_graph.processingChanges);
        }]];
    }];
}

- (void)testActionBlockRetainedUntilEndOfEvent {
    // NOTE: This works as an example of what can happen during an extent's dealloc, submit changes
    // can capture an array of behaviors the extent owns so when the action block goes out of
    // scope those behaviors and connected resources can be deallocated (causing new actions)
    // before the current one is complete
    // So we hold on to the action block internally to prevent this.
    //
    // - event 1 runs and creates side effect 1
    // - while event 1 is in side effect phase, an asynchronous action block is queued up
    // - myValue will now go out of scope but it is captured by the action block and that is retained internally
    // - so when we are running event 2 and side effect 2, myValue will still be around because it is
    //   retained until the end of the event
    __block NSString *description = nil;
    __block BOOL valDealloced = NO;
    
    [_graph action:@"event 1" runBlock:^{
        [_graph sideEffect:@"side effect 1" runBlock:^{
            @autoreleasepool {
                __auto_type myValue = [[TestOnDealloc alloc] initWithDeallocBlock:^{
                    valDealloced = YES;
                }];
                [_graph action:@"event 2" requireSync:NO runBlock:^{
                    description = myValue.description;
                    [_ext sideEffect:@"side effect 2" runBlock:^(id  _Nonnull extent) {
                        XCTAssertFalse(valDealloced);
                    }];
                }];
            }
        }];
    }];
}

- (void)testAddedResourceUpdatedWhenExtentIsAdded {
    // |> Given we have two behaviors one that demands added and one that doesnt
    __block BOOL aRun = NO;
    __block BOOL bRun = NO;
    
    [_ext behaviorWithDemands:nil supplies:nil runBlock:^(id  _Nonnull extent) {
        aRun = YES;
    }];
    [_ext behaviorWithDemands:@[_ext.added] supplies:nil runBlock:^(id  _Nonnull extent) {
        bRun = YES;
    }];
    
    // |> When the extent is added
    [_graph action:nil runBlock:^{
        [_ext addToGraph];
    }];
    
    // |> Added will activate one behavior but the other one won't run
    XCTAssertFalse(aRun);
    XCTAssertTrue(bRun);
}

@end
