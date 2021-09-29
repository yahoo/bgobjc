//
//  Copyright Yahoo 2021
//

#import "BGViewController.h"
#import <BehaviorGraph/BGGraph.h>
#import "LoginExtent.h"

@interface BGViewController ()
@property (nonatomic) BGGraph *graph;
@property (nonatomic) LoginExtent *loginExtent;
@end

@implementation BGViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    _graph = [[BGGraph alloc] init];
    _loginExtent = [[LoginExtent alloc] initWithGraph:_graph];
    _loginExtent.loginForm = self;
    [_graph action:@"new login page" runBlock:^{
        [self.loginExtent addToGraph];
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (IBAction)didUpdateEmailField:(id)sender {
    [self.graph action:@"update email" runBlock:^{
        [self.loginExtent.email updateValue:self.emailField.text];
    }];
}

- (IBAction)didUpdatePasswordField:(id)sender {
    [self.graph action:@"update password" runBlock:^{
        [self.loginExtent.password updateValue:self.passwordField.text];
    }];
}

- (IBAction)loginButtonClicked:(id)sender {
    [self.graph action:@"login button" runBlock:^{
        [self.loginExtent.loginClick update];
    }];
}

- (IBAction)loginSucceeded:(id)sender {
    [self.loginExtent completeLogin:YES];
}

- (IBAction)loginFailed:(id)sender {
    [self.loginExtent completeLogin:NO];
}

@end
