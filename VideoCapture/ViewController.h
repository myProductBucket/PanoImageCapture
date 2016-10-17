//
//  ViewController.h
//  VideoCapture
//
//  Created by Daniel Rastlos on 02/05/16.
//  Copyright © 2016 Daniel Rastlos. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef struct
{
    double x, y, z;
} RedPosition;

@interface ViewController : UIViewController

@property (strong, nonatomic) LLSimpleCamera *camera;

@property (weak, nonatomic) IBOutlet UIButton *snapButton;
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UIButton *switchButton;
@property (weak, nonatomic) IBOutlet UILabel *errorLabel;
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UIButton *startPanoButton;

@property (weak, nonatomic) IBOutlet UIImageView *crossHairImageV;
@end

