//
//  Copyright Yahoo 2021
//

@import UIKit;

@interface BGViewController : UIViewController

@property (nonatomic) IBOutlet UITextField *emailField;
@property (nonatomic) IBOutlet UITextField *passwordField;
@property (nonatomic) IBOutlet UIButton *loginButton;
@property (nonatomic) IBOutlet UILabel *emailFeedback;
@property (nonatomic) IBOutlet UILabel *passwordFeedback;
@property (nonatomic) IBOutlet UILabel *loginStatus;
@property (nonatomic) IBOutlet UIButton *loginSuccess;
@property (nonatomic) IBOutlet UIButton *loginFail;

@end
