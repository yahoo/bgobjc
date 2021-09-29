//
//  Copyright Yahoo 2021
//    

#import "LoginExtent.h"

@implementation LoginExtent

- (instancetype)initWithGraph:(BGGraph *)graph {
    self = [super initWithGraph:graph];
    
    _loggingIn = [self stateWithValue:@NO];
    _email = [self stateWithValue:nil];
    _password = [self stateWithValue:nil];
    _emailValid = [self stateWithValue:@NO];
    _passwordValid = [self stateWithValue:@NO];
    _emailValid = [self stateWithValue:@NO];
    _passwordValid = [self stateWithValue:@NO];
    _loginEnabled = [self stateWithValue:@NO];
    _loginClick = [self moment];
    _loginComplete = [self moment];

    
    [self behaviorWithDemands:@[self.email, self.added]
                     supplies:@[self.emailValid]
                     runBlock:^(LoginExtent * _Nonnull extent) {
        
        NSString *email = extent.email.value;
        BOOL emailValid = [LoginExtent validEmailAddress:email];
        [extent.emailValid updateValue:@(emailValid)];
        [extent sideEffect:@"email status" runBlock:^(LoginExtent * _Nonnull extent) {
            extent.loginForm.emailFeedback.text = extent.emailValid.value.boolValue ? @"✅" : @"❌";
        }];

    }];

    
    [self behaviorWithDemands:@[self.password, self.added]
                     supplies:@[self.passwordValid]
                     runBlock:^(LoginExtent * _Nonnull extent) {
       
        NSString *password = extent.password.value;
        BOOL passwordValid = password.length > 0;
        [extent.passwordValid updateValue:@(passwordValid)];
        [extent sideEffect:@"password status" runBlock:^(LoginExtent * _Nonnull extent) {
            extent.loginForm.passwordFeedback.text = extent.passwordValid.value.boolValue ? @"✅" : @"❌";
        }];
        
    }];


    [self behaviorWithDemands:@[self.emailValid, self.passwordValid, self.loggingIn, self.added]
                     supplies:@[self.loginEnabled]
                     runBlock:^(LoginExtent * _Nonnull extent) {
        
        BOOL enabled = (extent.emailValid.value.boolValue &&
                        extent.passwordValid.value.boolValue &&
                        !extent.loggingIn.value.boolValue);
        [extent.loginEnabled updateValue:@(enabled)];
        [extent sideEffect:@"enable login button" runBlock:^(LoginExtent * _Nonnull extent) {
            extent.loginForm.loginButton.enabled = extent.loginEnabled.value.boolValue;
        }];
        
    }];

    
    [self behaviorWithDemands:@[self.loginClick, self.loginComplete, self.added]
                     supplies:@[self.loggingIn]
                     runBlock:^(LoginExtent * _Nonnull extent) {
        
        if (extent.loginClick.justUpdated &&
            extent.loginEnabled.traceValue.boolValue) {
            // Start login
            [extent.loggingIn updateValue:@YES];
        } else if (extent.loginComplete.justUpdated &&
                   extent.loggingIn.value.boolValue) {
            // Complete login
            [extent.loggingIn updateValue:@NO];
        }

        if ([extent.loggingIn justUpdatedTo:@YES]) {
            [extent sideEffect:@"login api call" runBlock:^(LoginExtent * _Nonnull extent) {
                [extent login:extent.email.value password:extent.password.value complete:^(BOOL success) {
                    [extent.graph action:@"login complete" requireSync:NO runBlock:^{
                        [extent.loginComplete updateValue:@(success)];
                    }];
                }];
            }];
        }
        
    }];

    
    [self behaviorWithDemands:@[self.loggingIn, self.loginComplete, self.added]
                     supplies:nil
                     runBlock:^(LoginExtent * _Nonnull extent) {
        
        [extent sideEffect:@"login status" runBlock:^(LoginExtent * _Nonnull extent) {
            if (extent.loggingIn.value.boolValue) {
                extent.loginForm.loginStatus.text = @"Logging in...";
            } else {
                if ([extent.loginComplete justUpdatedTo:@YES]) {
                    extent.loginForm.loginStatus.text = @"Login Success";
                } else if ([extent.loginComplete justUpdatedTo:@NO]) {
                    extent.loginForm.loginStatus.text = @"Login Failed";
                } else {
                    extent.loginForm.loginStatus.text = nil;
                }
            }
        }];
        
    }];

    return self;
}

+ (BOOL)validEmailAddress:(NSString *)string {
    NSString *regex = @"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}";
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF matches %@", regex];
    return [pred evaluateWithObject:string];
}

- (void)login:(NSString *)email password:(NSString *)password complete:(void(^)(BOOL success))complete {
    self.savedLoginBlock = complete;
}

- (void)completeLogin:(BOOL)success {
    if (self.savedLoginBlock) {
        self.savedLoginBlock(success);
        self.savedLoginBlock = nil;
    }
}

@end
