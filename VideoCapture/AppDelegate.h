//
//  AppDelegate.h
//  VideoCapture
//
//  Created by Daniel Rastlos on 02/05/16.
//  Copyright © 2016 Daniel Rastlos. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic, readonly) CMMotionManager *sharedManager;

@end

