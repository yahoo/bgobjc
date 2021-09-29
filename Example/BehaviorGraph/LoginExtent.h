//
//  Copyright Yahoo 2021
//    

#import <Foundation/Foundation.h>
#import <BehaviorGraph/BGGraph.h>
#import "BGViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class LoginExtent;
@interface LoginExtent : BGExtent<LoginExtent*>

@property (nonatomic, readonly) BGState<NSString *> *email;
@property (nonatomic, readonly) BGState<NSString *> *password;
@property (nonatomic, readonly) BGMoment *loginClick;
@property (nonatomic, readonly) BGState<NSNumber *> *emailValid;
@property (nonatomic, readonly) BGState<NSNumber *> *passwordValid;
@property (nonatomic, readonly) BGState<NSNumber *> *loginEnabled;
@property (nonatomic, readonly) BGState<NSNumber *> *loggingIn;
@property (nonatomic, readonly) BGMoment<NSNumber *> *loginComplete;
@property (nonatomic, readwrite, nullable) void (^savedLoginBlock)(BOOL success);
@property (nonatomic, readwrite, weak) BGViewController *loginForm;

- (instancetype)initWithGraph:(BGGraph *)graph;
- (void)completeLogin:(BOOL)success;

@end

NS_ASSUME_NONNULL_END
