//
//  ViewController.m
//  VideoCapture
//
//  Created by Daniel Rastlos on 02/05/16.
//  Copyright © 2016 Daniel Rastlos. All rights reserved.
//

#import "ViewController.h"

#define EXT_MOV @".MOV"
#define EXT_METATXT @"_meta.TXT"
#define EXT_ACCETXT @"_accelerometer.TXT"
#define EXT_GYROTXT @"_gyroscope.TXT"

//#define TOTALKEEP 5
#define EXPOSURE 1
#define INTERVAL_ANGLE M_PI / 6.0
#define VFOV M_PI / 6.0
#define HFOV M_PI / 12.0

#define POSENUM 15
#define ANGLE 24.00 * M_PI / 180.0f

#define RATIO 1.3333

#define TimeStamp [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970] * 1000]
#define FileURL [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject]

@interface ViewController () {
    
    NSURL *tmpVideoURL;
    NSString *currentFileName;
    
//    NSDate *startDate;
//    NSDate *endDate;
    NSString *startTimeStamp;
    NSString *endTimeStamp;
    
    NSString *accelerStr;
    NSString *gyroStr;
    
    NSTimer *myTimer;
    NSInteger totalCount;
    
    // Manage the red dot view
    BOOL isStarted;
    
    UIView *redDotView;// Red Dot View
    UIImageView *recordingImageV;
    
    CMDeviceMotion *curDeviceMotion;
    CMDeviceMotion *befDeviceMotion;
    CMDeviceMotion *baseDeviceMotion;
    
    CMAccelerometerData *curAccelerData;
    CMAccelerometerData *befAccelerData;
    CMAccelerometerData *baseAccelerData;
    
    double baseRotationD;
    double baseTiltD;
    
    RedPosition basePos;
    
    double facialLen; // Unit : Pixel
    
    NSInteger panoIndex; // Pano Image Index
//    NSInteger posIndex;  // it will have 12 poses
//    NSInteger keepIndex; // keep number of cener position of Red Dot View; For keeping 500 ms
    
    NSArray *exposureArray;
    
    // White balance and gain RGB
    AVCaptureWhiteBalanceTemperatureAndTintValues currentColorTemperature; // Temperature and Tint
}

@end

@implementation ViewController

static void *ExposureTargetOffsetContext = &ExposureTargetOffsetContext;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initUI];
    // Do any additional setup after loading the view, typically from a nib.
    exposureArray = @[@"1000", @"200", @"80", @"35", @"15"];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    
    // ----- initialize camera -------- //
    
    // create camera vc
    self.camera = [[LLSimpleCamera alloc] initWithQuality:AVCaptureSessionPresetHigh
                                                 position:LLCameraPositionRear
                                             videoEnabled:YES];
//    [self addObserver:self forKeyPath:@"self.camera.videoCaptureDevice.exposureTargetOffset" options:NSKeyValueObservingOptionNew context:ExposureTargetOffsetContext];

    [self initTemperatureAndSetWhiteBalance];
    
    // attach to a view controller
    [self.camera attachToViewController:self withFrame:CGRectMake(0, 0, screenRect.size.width, screenRect.size.width * RATIO)];
    
    // you probably will want to set this to YES, if you are going view the image outside iOS.
    self.camera.fixOrientationAfterCapture = NO;
    
    if ([self.camera.videoCaptureDevice respondsToSelector:@selector(isAutoFocusRangeRestrictionSupported)] && self.camera.videoCaptureDevice.autoFocusRangeRestrictionSupported) {
        // If we are on an iOS version that supports AutoFocusRangeRestriction and the device supports it
        // Set the focus range to "near"
        if ([self.camera.videoCaptureDevice lockForConfiguration:nil]) {
            self.camera.videoCaptureDevice.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionFar;
            [self.camera.videoCaptureDevice unlockForConfiguration];
        }
    }
    
    // take the required actions on a device change
    __weak typeof(self) weakSelf = self;
    [self.camera setOnDeviceChange:^(LLSimpleCamera *camera, AVCaptureDevice * device) {
        
        NSLog(@"Device changed.");
        
        // device changed, check if flash is available
        if([camera isFlashAvailable]) {
            weakSelf.flashButton.hidden = NO;
            
            if(camera.flash == LLCameraFlashOff) {
                weakSelf.flashButton.selected = NO;
            }
            else {
                weakSelf.flashButton.selected = YES;
            }
        }
        else {
            weakSelf.flashButton.hidden = YES;
        }
    }];
    
    [self.camera setOnError:^(LLSimpleCamera *camera, NSError *error) {
        NSLog(@"Camera error: %@", error);
        
        if([error.domain isEqualToString:LLSimpleCameraErrorDomain]) {
            if(error.code == LLSimpleCameraErrorCodeCameraPermission ||
               error.code == LLSimpleCameraErrorCodeMicrophonePermission) {
                
                if(weakSelf.errorLabel) {
                    [weakSelf.errorLabel removeFromSuperview];
                }
                
                UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
                label.text = @"We need permission for the camera.\nPlease go to your settings.";
                label.numberOfLines = 2;
                label.lineBreakMode = NSLineBreakByWordWrapping;
                label.backgroundColor = [UIColor clearColor];
                label.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:13.0f];
                label.textColor = [UIColor whiteColor];
                label.textAlignment = NSTextAlignmentCenter;
                [label sizeToFit];
                label.center = CGPointMake(screenRect.size.width / 2.0f, screenRect.size.height / 2.0f);
                weakSelf.errorLabel = label;
                [weakSelf.view addSubview:weakSelf.errorLabel];
            }
        }
    }];
    
    // snap button to capture image
    self.snapButton.clipsToBounds = YES;
    self.snapButton.layer.cornerRadius = self.snapButton.width / 2.0f;
    self.snapButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.snapButton.layer.borderWidth = 2.0f;
    self.snapButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    self.snapButton.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.snapButton.layer.shouldRasterize = YES;
    [self.snapButton setTag:0];
    
    // button to toggle flash
    self.flashButton.tintColor = [UIColor whiteColor];
    
    if([LLSimpleCamera isFrontCameraAvailable] && [LLSimpleCamera isRearCameraAvailable]) {
        // button to toggle camera positions
        self.switchButton.tintColor = [UIColor whiteColor];
        self.switchButton.imageEdgeInsets = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f);
    }
    
    // Start Pano Button Hidden
    [self.startPanoButton setHidden:YES];
    [self.startPanoButton setAlpha:0];
    
    // Add the dot view to Main View
    [self addRedDotToView];
    
    // Add Recording Image View To Main View
    [self addRecordingImage];
    
    isStarted = NO;
    
    panoIndex = 0;
//    if (![self.camera isFlashAvailable]) {
//        [self.flashButton setHidden:YES];
//    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
//    self.camera.view.frame = self.view.contentBounds;
    [self initUI];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self initUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // start the camera
    [self.camera start];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Capture Device Call Back

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    
    if (context == ExposureTargetOffsetContext){
        float newExposureTargetOffset = [change[NSKeyValueChangeNewKey] floatValue];
        NSLog(@"Offset is : %f",newExposureTargetOffset);
        
        if(!self.camera.videoCaptureDevice) return;
        
        CGFloat currentISO = self.camera.videoCaptureDevice.ISO;
        CGFloat biasISO = 0;
        
        //Assume 0,3 as our limit to correct the ISO
        if(newExposureTargetOffset > 0.3f) //decrease ISO
            biasISO = -50;
        else if(newExposureTargetOffset < -0.3f) //increase ISO
            biasISO = 50;
        
        if(biasISO){
            //Normalize ISO level for the current device
            CGFloat newISO = currentISO+biasISO;
            newISO = newISO > self.camera.videoCaptureDevice.activeFormat.maxISO? self.camera.videoCaptureDevice.activeFormat.maxISO : newISO;
            newISO = newISO < self.camera.videoCaptureDevice.activeFormat.minISO? self.camera.videoCaptureDevice.activeFormat.minISO : newISO;
            
            NSError *error = nil;
            if ([self.camera.videoCaptureDevice lockForConfiguration:&error]) {
                [self.camera.videoCaptureDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:newISO completionHandler:^(CMTime syncTime) {}];
                [self.camera.videoCaptureDevice unlockForConfiguration];
            }
        }
    }
}

#pragma mark - Custom Events

- (IBAction)startPanoButtonTouchUp:(UIButton *)sender {
    
    panoIndex ++;

    baseDeviceMotion = curDeviceMotion;
    befDeviceMotion = curDeviceMotion;
    
    baseAccelerData = curAccelerData;
    
    baseRotationD = [self getCurrentRotationDegree:curDeviceMotion];
    baseTiltD = [self getCurrentTiltDegree:curDeviceMotion withAccelerationData:curAccelerData];
    
    double fov = self.camera.videoCaptureDevice.activeFormat.videoFieldOfView;
    double radianFOV = fov * M_PI / 180;
    facialLen = [[UIScreen mainScreen] bounds].size.height / 2 / tan(radianFOV / 2);
    
    RedPosition curPos;
    curPos.x = 0;
    curPos.y = 0;
    curPos.z = - facialLen;
    basePos = [self getRealPosition:baseDeviceMotion withPos:curPos];
    
    [self showRedDotView];// Show Red Dot View
    [self moveRedDotViewToX:0 andY:0];// Move Red Dot View
    
    isStarted = YES;
    
    [self hideStartPanoButton];
}

// -x -> -y -> -z
- (RedPosition)getRealPosition: (CMDeviceMotion *)motion withPos: (RedPosition)curPos {
    RedPosition pos;
    double p = - motion.attitude.pitch;
    double r = - motion.attitude.roll;
    double w = - motion.attitude.yaw;
    
    pos.x = curPos.x * cos(r) * cos(w) - sin(r) * cos(w) * (curPos.z * cos(p) - curPos.y * sin(p)) + sin(w) * (curPos.y * cos(p) + curPos.z * sin(p));
    
    pos.y = - curPos.x * cos(r) * sin(w) + sin(r) * sin(w) * (curPos.z * cos(p) - curPos.y * sin(p)) + cos(w) * (curPos.y * cos(p) + curPos.z * sin(p));
    
    pos.z = curPos.x * sin(r) + cos(r) * (curPos.z * cos(p) - curPos.y * sin(p));
    
    return pos;
}

// z -> y -> x
- (RedPosition)getVirtualPosition: (CMDeviceMotion *)motion {
    RedPosition pos;
    double p = motion.attitude.pitch;
    double r = motion.attitude.roll;
    double w = motion.attitude.yaw;
    
    pos.x = (basePos.x * cos(w) + basePos.y * sin(w)) * cos(r) - basePos.z * sin(r);
    
    pos.y = cos(p) * (basePos.y * cos(w) - basePos.x * sin(w)) + sin(p) * ((basePos.x * cos(w) + basePos.y * sin(w)) * sin(r) + basePos.z * cos(r));
    
    pos.z = - sin(p) * (basePos.y * cos(w) - basePos.x * sin(w)) + cos(p) * ((basePos.x * cos(w) + basePos.y * sin(w)) * sin(r) + basePos.z * cos(r));
    
    return pos;
}

- (void)moveRedDotViewToX: (CGFloat)x andY: (CGFloat)y {
    CGFloat w = [[UIScreen mainScreen] bounds].size.width;
    CGFloat h = w * RATIO;//[[UIScreen mainScreen] bounds].size.height;
    CGFloat rw = redDotView.frame.size.width;
    CGFloat rh = redDotView.frame.size.height;
    CGFloat xx = x + (w - rw) / 2;
    CGFloat yy = (h - rh) / 2 - y;
    
    if (xx < 0) {
        xx = 0;
    }
    if (xx > w) {
        xx = w - rw;
    }
    if (yy < 0) {
        yy = 0;
    }
    if (yy > h) {
        yy = h - rh;
    }
    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [redDotView setFrame:CGRectMake(xx, yy, rw, rh)];
    } completion:^(BOOL finished) {
        
    }];
}

- (void)showRedDotView {
    [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [redDotView setHidden:NO];
        [redDotView setAlpha:1];
    } completion:^(BOOL finished) {
        
    }];
}

- (void)hideRedDotView {
    [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [redDotView setAlpha:0];
    } completion:^(BOOL finished) {
        [redDotView setHidden:YES];
    }];
}

- (IBAction)snapButtonTouchUp:(UIButton *)sender {
    

        if(self.snapButton.tag == 0) {//!self.camera.isRecording

            self.flashButton.hidden = YES;
            self.switchButton.hidden = YES;
            
            self.snapButton.layer.borderColor = [UIColor redColor].CGColor;
            self.snapButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
            [self.snapButton setTag:1];
            
            // start recording
            [self showAlertToSetName];
            
            panoIndex = 0;
        } else {

            self.flashButton.hidden = NO;
            self.switchButton.hidden = NO;
            
            if (![self.camera isFlashAvailable]) {
                [self.flashButton setHidden:YES];
            }
            
            self.snapButton.layer.borderColor = [UIColor whiteColor].CGColor;
            self.snapButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
            [self.snapButton setTag:0];
            
//            endDate = [self getLocalDate];
            
            [self stopUpdates];
            
            [myTimer invalidate];
            
            [self.timeLabel setText:@"00:00"];
            
            //saving accelerometer data and Gyroscope Data
            [self saveCaptureInfo];
            
            [self showErrorAlertWithString:[NSString stringWithFormat:@"The capture file(%@) was saved successfully!", currentFileName]];
            
            // Hide Start Pano Button
            [self hideStartPanoButton];
            [self hideRedDotView];
            
//            [self.camera stopRecording:^(LLSimpleCamera *camera, NSURL *outputFileUrl, NSError *error) {
//                
//                if (error) {
//                    NSLog(@"Stop Recording Error: %@", error.description);
//                    [self showErrorAlertWithString:@"Unknown error was occured!\nPlease try again."];
//                }else{
//                    
////                    NSURL *fileURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
//                    
//                    //saving accelerometer data and Gyroscope Data
//                    [self saveCaptureInfo];
//                    
//                    //saving metadata data
//                    AVAsset *videoAsset = (AVAsset *)[AVAsset assetWithURL:outputFileUrl];
//                    AVAssetTrack *videoAssetTrack;
//                    if ([videoAsset tracksWithMediaType:AVMediaTypeVideo]) {
//                        videoAssetTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
//                    }
//                    NSLog(@"%f", CMTimeGetSeconds(videoAssetTrack.timeRange.duration));
//                    
//                    NSURL *fullURL = [NSURL URLWithString:[[FileURL absoluteString] stringByAppendingString:[NSString stringWithFormat:@"%@%@", currentFileName, EXT_METATXT]]];
//                    NSString *metaStr = [NSString stringWithFormat:@"\nStart Time: %f", startTimeStamp];
//                    metaStr = [NSString stringWithFormat:@"%@\nEnd Time: %f", metaStr, endTimeStamp];
//                    metaStr = [NSString stringWithFormat:@"%@\n\nDuration: %fs", metaStr, CMTimeGetSeconds(videoAssetTrack.timeRange.duration)];
//                    metaStr = [NSString stringWithFormat:@"%@\n\nDimension Width: %f", metaStr, [videoAssetTrack naturalSize].width];
//                    metaStr = [NSString stringWithFormat:@"%@\nDimension Height: %f", metaStr, [videoAssetTrack naturalSize].height];
//                    metaStr = [NSString stringWithFormat:@"%@\n\nFrame Rate: %f", metaStr, [videoAssetTrack nominalFrameRate]];
//                    metaStr = [NSString stringWithFormat:@"%@\nBPS Rate: %f", metaStr, [videoAssetTrack estimatedDataRate]];
//                    
//                    NSArray<AVMetadataItem *> *metaData = [videoAssetTrack metadata];
//                    for (AVMetadataItem *item in metaData) {
//                        NSLog(@"%@", item);
//                    }
//                    
//                    NSArray<AVAssetTrackSegment *> *segments = [videoAssetTrack segments];
//                    for (AVAssetTrackSegment *item in segments) {
//                        if (![item isEmpty]) {
//                            NSLog(@"%lld", item.timeMapping.source.duration.value);
//                            metaStr = [NSString stringWithFormat:@"%@\n\nSource Time Range Start: %lld", metaStr, item.timeMapping.source.start.value];
//                            metaStr = [NSString stringWithFormat:@"%@\nSource Time Range Duration: %lld", metaStr, item.timeMapping.source.duration.value];
//                            metaStr = [NSString stringWithFormat:@"%@\n\nTarget Time Range Start: %lld", metaStr, item.timeMapping.target.start.value];
//                            metaStr = [NSString stringWithFormat:@"%@\nTarget Time Range Duration: %lld", metaStr, item.timeMapping.target.duration.value];
//                        }
//                    }
//                    
//                    metaStr = [NSString stringWithFormat:@"%@\n\nDevice Type(Platform): %@", metaStr, [UIDeviceHardware platformString]];
//                    
//                    //---
//                    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
//                    AVCaptureDeviceInput *capInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
//                    AVCaptureDeviceFormat *capFormat = capInput.device.activeFormat;
//                    CMFormatDescriptionRef fDesc = capFormat.formatDescription;
//                    CGSize dim = CMVideoFormatDescriptionGetPresentationDimensions(fDesc, YES, YES);
//                    
//                    metaStr = [NSString stringWithFormat:@"%@\n\ncx = %f", metaStr, (CGFloat)dim.width / 2.0f];
//                    metaStr = [NSString stringWithFormat:@"%@\ncy = %f", metaStr, (CGFloat)dim.height / 2.0f];
//                    
//                    metaStr = [NSString stringWithFormat:@"%@\n\nHFOV = %f", metaStr, capFormat.videoFieldOfView];
//                    metaStr = [NSString stringWithFormat:@"%@\nVFOV = %f", metaStr, capFormat.videoFieldOfView * dim.height / dim.width];
//                    
//                    CGFloat fx = fabs(dim.width / (2 * tan(capFormat.videoFieldOfView / 180 * M_PI / 2)));
//                    CGFloat fy = fabs(dim.height / (2 * tan (capFormat.videoFieldOfView / 180 * M_PI / 2 * dim.height / dim.width)));
//                    
//                    metaStr = [NSString stringWithFormat:@"%@\n\nfx = %f", metaStr, fx];
//                    metaStr = [NSString stringWithFormat:@"%@\nfy = %f", metaStr, fy];
//                    
//                    [metaStr writeToURL:fullURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
//                    
//                    [self showErrorAlertWithString:[NSString stringWithFormat:@"The video file(%@.MOV) was saved successfully!", currentFileName]];
//                }
//            }];
        }

}

- (IBAction)flashButtonTouchUp:(UIButton *)sender {
    if(self.camera.flash == LLCameraFlashOff) {
        BOOL done = [self.camera updateFlashMode:LLCameraFlashOn];
        if(done) {
            self.flashButton.selected = YES;
            self.flashButton.tintColor = [UIColor yellowColor];
            [self.flashButton setImage:[UIImage imageNamed:@"Camera_Flash_On"] forState:UIControlStateNormal];
        }
    }
    else {
        BOOL done = [self.camera updateFlashMode:LLCameraFlashOff];
        if(done) {
            self.flashButton.selected = NO;
            self.flashButton.tintColor = [UIColor whiteColor];
            [self.flashButton setImage:[UIImage imageNamed:@"Camera_Flash"] forState:UIControlStateNormal];
        }
    }
}

- (IBAction)switchButtonTouchUp:(UIButton *)sender {
    
//    [UIView animateWithDuration:3.0 delay:0.0 options:UIViewAnimationOptionAutoreverse animations:^{
////        [self.view setCenter:CGPointMake(0, 0)];
//    } completion:^(BOOL finished) {
        [self.camera togglePosition];
//    }];
}

#pragma mark - Custom Event

- (void)initUI {
    CGFloat w = [[UIScreen mainScreen] bounds].size.width;
//    CGFloat h = [[UIScreen mainScreen] bounds].size.height;
    
    [self.crossHairImageV setFrame:CGRectMake(0, 0, w, w * RATIO)];
    [self.startPanoButton setFrame:CGRectMake((w - 81) / 2, (w * RATIO - 81) / 2, 81, 81)];
    [self.crossHairImageV setNeedsLayout];
    [self.startPanoButton setNeedsLayout];
}

- (void)initTemperatureAndSetWhiteBalance {
    currentColorTemperature.temperature = 5500;
    currentColorTemperature.tint = 0;
    
    [self setWhiteBalanceGains:[self.camera.videoCaptureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:currentColorTemperature]];
}

- (void)setWhiteBalanceGains: (AVCaptureWhiteBalanceGains)gains {
    NSError *error = nil;
    
    [self.camera.videoCaptureDevice lockForConfiguration:&error];
    
    if (error == nil) {
        [self.camera.videoCaptureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:nil];
        [self.camera.videoCaptureDevice unlockForConfiguration];
    }
    if ([self.camera.videoCaptureDevice lockForConfiguration:&error]) {
    }
}

- (RedPosition)getPositionWithDeviceMotion: (CMDeviceMotion *)deviceMotion {
    RedPosition redPos;
    double rotationDegree = [self getCurrentRotationDegree:deviceMotion];
    double tiltDegree = [self getCurrentTiltDegree:deviceMotion withAccelerationData:curAccelerData];
    double realRotation = rotationDegree + (M_PI - baseRotationD);
    if (realRotation > (2 * M_PI)) {
        realRotation = realRotation - 2 * M_PI;
    }else if (realRotation < 0) {
        realRotation = realRotation + 2 * M_PI;
    }
    
    double realTilt = tiltDegree + (M_PI - baseTiltD);
    if (realTilt > (2 * M_PI)) {
        realTilt = realTilt - 2 * M_PI;
    }else if (realTilt < 0) {
        realTilt = realTilt + 2 * M_PI;
    }
    
    CGFloat tilt = (M_PI - realTilt) / M_PI * 180;
    CGFloat vfov = VFOV / M_PI * 180;
    CGFloat rotation = (M_PI - realRotation) / M_PI * 180;
    CGFloat hfov = HFOV / M_PI * 180;
    
    double w = [[UIScreen mainScreen] bounds].size.width;
    double h = [[UIScreen mainScreen] bounds].size.height;
    
    redPos.y = h * tilt / vfov;
    redPos.x = w * rotation / hfov;
    return redPos;
}

- (double)getCurrentRotationDegree: (CMDeviceMotion *)deviceMotion{
    double rotationDegree = deviceMotion.attitude.roll + deviceMotion.attitude.yaw;
    if (rotationDegree < 0) {
        rotationDegree = 2 * M_PI + rotationDegree;
    }
    return rotationDegree;
}

- (double)getCurrentTiltDegree: (CMDeviceMotion *)deviceMotion withAccelerationData: (CMAccelerometerData *)accelerData {
    double tiltDegree = deviceMotion.attitude.pitch;
    if (accelerData.acceleration.z > 0) {
        tiltDegree = M_PI - tiltDegree;
    }else if (accelerData.acceleration.z < 0 && tiltDegree < 0) {
        tiltDegree = 2 * M_PI + tiltDegree;
    }
    return tiltDegree;
}

- (void)saveCaptureInfo {
    //saving accelerometer data
    NSURL *fullURL = [NSURL URLWithString:[[FileURL absoluteString] stringByAppendingString:[NSString stringWithFormat:@"%@%@", currentFileName, EXT_ACCETXT]]];
    [accelerStr writeToURL:fullURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    //saving gyroscope data
    fullURL = [NSURL URLWithString:[[FileURL absoluteString] stringByAppendingString:[NSString stringWithFormat:@"%@%@", currentFileName, EXT_GYROTXT]]];
    [gyroStr writeToURL:fullURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)moveBasePosToNext {
//    RedPosition newPos;
//    newPos.x = basePos.x * cos(INTERVAL_ANGLE) + basePos.y * sin(INTERVAL_ANGLE);
//    newPos.y = - basePos.x * sin(INTERVAL_ANGLE) + basePos.y * cos(INTERVAL_ANGLE);
//    newPos.z = basePos.z;
//    basePos = newPos;
    baseRotationD = baseRotationD - ANGLE;
    if (baseRotationD < 0) {
        baseRotationD = 2 * M_PI + baseRotationD;
    }
}

- (void)getPanoImagesWithIndex: (NSInteger)ind {
    
//    for (NSInteger i = 0; i < EXPOSURE; i++) {
//        while (self.camera.videoCaptureDevice.adjustingExposure) {
//            
//        }
        [self captureImageWithIndex:0 poseIndex:ind];
//    }
}

- (void)captureImageWithIndex: (NSInteger)exposureIndex poseIndex: (NSInteger)poseIndex {
    // capture
//    CMTime cmTime = CMTimeMake(1, [exposureArray[exposureIndex] intValue]);
    if (self.camera.videoCaptureDevice == nil) {
        return;
    }
//    float newExposureTargetOffset = self.camera.videoCaptureDevice.exposureTargetOffset;
//    
//    CGFloat currentISO = self.camera.videoCaptureDevice.ISO;
//    CGFloat biasISO = 0;
//    
//    //Assume 0,3 as our limit to correct the ISO
//    if(newExposureTargetOffset > 0.1f) //decrease ISO
//        biasISO = -50;
//    else if(newExposureTargetOffset < -0.1f) //increase ISO
//        biasISO = 50;
//    
//    if(biasISO){
//        //Normalize ISO level for the current device
//        CGFloat newISO = currentISO+biasISO;
//        newISO = newISO > self.camera.videoCaptureDevice.activeFormat.maxISO? self.camera.videoCaptureDevice.activeFormat.maxISO : newISO;
//        newISO = newISO < self.camera.videoCaptureDevice.activeFormat.minISO? self.camera.videoCaptureDevice.activeFormat.minISO : newISO;
    
        NSError *error = nil;
        if ([self.camera.videoCaptureDevice lockForConfiguration:&error]) {
            
            self.camera.videoCaptureDevice.exposureMode = 2;
            
//            [self.camera.videoCaptureDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:newISO completionHandler:^(CMTime syncTime) {}];
            [self.camera.videoCaptureDevice unlockForConfiguration];
        }
//    }
    
    [self.camera capture:^(LLSimpleCamera *camera, UIImage *image, NSDictionary *metadata, NSError *error) {
        if(!error) {
            
//            UIImage *capturedImage = image;
//            
//            /* Render the screen shot at custom resolution */
//            CGRect cropRect = CGRectMake(0 ,0 ,capturedImage.size.width * 2.8 ,capturedImage.size.width * 2.8 * 1.3333);
//            UIGraphicsBeginImageContextWithOptions(cropRect.size, 1.0f, 1.0f);
//            [capturedImage drawInRect:cropRect];
//            UIImage * customImage = UIGraphicsGetImageFromCurrentImageContext();
//            UIGraphicsEndImageContext();
            // We should stop the camera, we are opening a new vc, thus we don't need it anymore.
            // This is important, otherwise you may experience memory crashes.
            // Camera is started again at viewWillAppear after the user comes back to this view.
            // I put the delay, because in iOS9 the shutter sound gets interrupted if we call it directly.
            //            [camera performSelector:@selector(stop) withObject:nil afterDelay:0.2];
            //                NSData *imageData = UIImagePNGRepresentation(image);
            NSData *imageData = UIImageJPEGRepresentation(image, 1);
            NSURL *savedURL = [NSURL URLWithString:[[FileURL absoluteString] stringByAppendingString:[NSString stringWithFormat:@"%@_%ld_%ld_%ld_%@.png", currentFileName, (long)panoIndex, (long)poseIndex, (long)(exposureIndex + 1), TimeStamp]]];
            
            [imageData writeToURL:savedURL atomically:YES];
            
            if (exposureIndex == EXPOSURE - 1) {
                [self.camera stop];
                
                [self hideRecordingImage];
                // start the camera
                [self.camera start];
                
                // Running after captured successfully
                [self moveBasePosToNext];
                
                isStarted = YES;
                
                if (poseIndex == POSENUM) {// Stop Getting Pano Images for new stuff
                    [self hideRedDotView];
                    [self showStartPanoButton];
                    isStarted = NO;
                    
                }
            }else if (exposureIndex < (EXPOSURE - 1)){
                [self captureImageWithIndex:(exposureIndex + 1) poseIndex:poseIndex];
            }
        }
        else {
            NSLog(@"An error has occured: %@", error);
        }
    } exactSeenImage:YES];
}

- (void)addRedDotToView {
    CGFloat w = [[UIScreen mainScreen] bounds].size.width;
    CGFloat h = w * RATIO;//[[UIScreen mainScreen] bounds].size.height;
    
    redDotView = [[UIView alloc] initWithFrame:CGRectMake((w - w / 20) / 2, (h - w / 20) / 2, w / 20, w / 20)];
    [redDotView setBackgroundColor:[UIColor redColor]];
    [redDotView.layer setCornerRadius:w / 40];
    [redDotView.layer setBorderColor:[UIColor redColor].CGColor];
    [redDotView.layer setBorderWidth:1];
    
    [redDotView setHidden:YES];
    [redDotView setAlpha:0];
    
    [self.view addSubview:redDotView];
}

- (void)addRecordingImage {
    CGFloat w = [[UIScreen mainScreen] bounds].size.width;
    CGFloat h = w * RATIO;//[[UIScreen mainScreen] bounds].size.height;
    
    recordingImageV = [[UIImageView alloc] initWithFrame:CGRectMake((w - w / 4) / 2, (h - w  * 57 / 284) / 2, w / 4, w * 57 / 284)];
    
    [recordingImageV setImage:[UIImage imageNamed:@"recording.png"]];
    
    [recordingImageV setHidden:YES];
    [recordingImageV setAlpha:0];
    
    [self.view addSubview:recordingImageV];
}

- (void)showRecordingImage {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [recordingImageV setAlpha:1];
        [recordingImageV setHidden:NO];
    } completion:^(BOOL finished) {
        
    }];
}

- (void)hideRecordingImage {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [recordingImageV setAlpha:0];
    } completion:^(BOOL finished) {
        [recordingImageV setHidden:YES];
    }];
}

- (void)showStartPanoButton {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.startPanoButton setAlpha:1];
        [self.startPanoButton setHidden:NO];
    } completion:^(BOOL finished) {
        
    }];
}

- (void)hideStartPanoButton {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.startPanoButton setAlpha:0];
    } completion:^(BOOL finished) {
        [self.startPanoButton setHidden:YES];
    }];
}

- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (void)showAlertWithData: (NSData *)sender {
    UIAlertController *alertVC = [UIAlertController alertControllerWithTitle:@"Register" message:@"Please set the file name!" preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textF = alertVC.textFields[0];
        if ([self checkText:textF.text]) {
            //saving video capture data
//            NSURL *fileURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
            NSURL *fileURL = [NSURL URLWithString:[[FileURL absoluteString] stringByAppendingString:[NSString stringWithFormat:@"%@%@", textF.text, EXT_MOV]]];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:fileURL.absoluteString]) {
                [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
            }
            
            [sender writeToURL:fileURL atomically:YES];
            
            //saving other text files
        }else{
            [self presentViewController:alertVC animated:YES completion:nil];
        }
    }];
    
    [alertVC addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        [textField setPlaceholder:@"Filename"];
    }];
    
    [alertVC addAction:ok];
    
    [self presentViewController:alertVC animated:YES completion:nil];
}

- (void)showAlertToSetName {
    UIAlertController *alertC = [UIAlertController alertControllerWithTitle:@"" message:@"Please set your file name!" preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textF = alertC.textFields[0];
        if ([self checkText:textF.text]) {
            //saving video capture data
//            NSURL *fileURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];

            tmpVideoURL = [FileURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@%@", textF.text, EXT_MOV] isDirectory:NO];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:tmpVideoURL.path]) {
                [alertC setMessage:@"This file name is already existed!"];
                [textF setText:@""];
                [self presentViewController:alertC animated:YES completion:nil];
            }else{
                currentFileName = textF.text;
                
//                [self.camera startRecordingWithOutputUrl:tmpVideoURL];
                
//                startDate = [self getLocalDate];
                
                accelerStr = [[NSString alloc] init];
                gyroStr = [[NSString alloc] init];
                
//                [self startUpdatesGyroWithSliderValue];
                [self startUpdatesAccelerWithSliderValue];
                [self startUpdatesWithSliderValue];
                
                totalCount = 0;
                myTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(settingTimeLabel) userInfo:nil repeats:YES];
            }
            
            //            [self refreshSandbox];//removing temporary files in tmp folder
            
            //saving other text files
            
            // Show Start Pano Button
            [self showStartPanoButton];
        }else{
            [alertC setMessage:@"Please set the valid file name!"];
            [textF setText:@""];
            [self presentViewController:alertC animated:YES completion:nil];
        }
    }];
    
    [alertC addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        [textField setPlaceholder:@"Filename"];
    }];
    
    [alertC addAction:ok];
    
    [self presentViewController:alertC animated:YES completion:nil];
}

- (void)showErrorAlertWithString: (NSString *)msg {
    UIAlertController *alertC = [UIAlertController alertControllerWithTitle:@"" message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        
    }];
    [alertC addAction:ok];
    
    [self presentViewController:alertC animated:YES completion:nil];
}

- (BOOL)checkText: (NSString *)text {
    NSString *rawString = text;
    NSCharacterSet *whiteSpace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmed = [rawString stringByTrimmingCharactersInSet:whiteSpace];
    if ([trimmed length] == 0) {
        return NO;
    }
    return YES;
}

- (NSDate *)getLocalDate {
    NSDate *sourceDate = [NSDate date];
    
    NSTimeZone *sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    NSTimeZone *destinationTimeZone = [NSTimeZone systemTimeZone];
    
    NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
    NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
//    interval = destinationGMTOffset - sourceGMTOffset;
    
    NSDate *destinationDate = [[NSDate alloc] initWithTimeInterval:(destinationGMTOffset - sourceGMTOffset) sinceDate:sourceDate];
    
    return destinationDate;
}

- (void)settingTimeLabel {
    totalCount++;
    NSInteger min = totalCount / 60;
    NSInteger sec = totalCount % 60;
    NSString *minStr;
    NSString *secStr;
    if (min < 10) {
        minStr = [NSString stringWithFormat:@"0%ld", (long)min];
    }else{
        minStr = [NSString stringWithFormat:@"%ld", (long)min];
    }
    if (sec < 10) {
        secStr = [NSString stringWithFormat:@"0%ld", (long)sec];
    }else{
        secStr = [NSString stringWithFormat:@"%ld", (long)sec];
    }
    
    [self.timeLabel setText:[NSString stringWithFormat:@"%@:%@", minStr, secStr]];
}

#pragma mark - Appcelerometer

- (void)startUpdatesAccelerWithSliderValue
{
//    NSTimeInterval delta = 0.005;
    NSTimeInterval updateInterval = 0.02;
    
    CMMotionManager *mManager = [(AppDelegate *)[[UIApplication sharedApplication] delegate] sharedManager];
    
//    ViewController * __weak weakSelf = self;
    if ([mManager isAccelerometerAvailable] == YES) {
        [mManager setAccelerometerUpdateInterval:updateInterval];
        [mManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMAccelerometerData *accelerometerData, NSError *error) {

            if ([accelerStr isEqualToString:@""]) {
                startTimeStamp = TimeStamp;//accelerometerData.timestamp;
            }
            endTimeStamp = TimeStamp;//accelerometerData.timestamp;
            
            accelerStr = [NSString stringWithFormat:@"%@\nX=%f Y=%f Z=%f: %@"
                                                , accelerStr
                                                , accelerometerData.acceleration.x
                                                , accelerometerData.acceleration.y
                                                , accelerometerData.acceleration.z
                          , TimeStamp];//[self getLocalDate];//accelerometerData.timestamp
            curAccelerData = accelerometerData;
        }];
    }
}

- (void)startUpdatesGyroWithSliderValue
{
//    NSTimeInterval delta = 0.005;
    NSTimeInterval updateInterval = 0.025;
    
    CMMotionManager *mManager = [(AppDelegate *)[[UIApplication sharedApplication] delegate] sharedManager];
    
//    ViewController * __weak weakSelf = self;
    if ([mManager isGyroAvailable] == YES) {
        [mManager setGyroUpdateInterval:updateInterval];
        [mManager startGyroUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMGyroData *gyroData, NSError *error) {

            gyroStr = [NSString stringWithFormat:@"%@\nX=%f Y=%f Z=%f: %@"
                          , gyroStr
                          , gyroData.rotationRate.x
                          , gyroData.rotationRate.y
                          , gyroData.rotationRate.z
                          , TimeStamp];//[self getLocalDate]///gyroData.timestamp
        }];
    }
    
//    self.updateIntervalLabel.text = [NSString stringWithFormat:@"%f", updateInterval];
}

- (void)startUpdatesWithSliderValue
{
//    NSTimeInterval delta = 0.005;
    NSTimeInterval updateInterval = 0.025;
    NSInteger totalKeep = 0.5 / updateInterval;
    
    CMMotionManager *mManager = [(AppDelegate *)[[UIApplication sharedApplication] delegate] sharedManager];
    
//    UIViewController * __weak weakSelf = self;
    
    if ([mManager isDeviceMotionAvailable] == YES) {
        [mManager setDeviceMotionUpdateInterval:updateInterval];
        [mManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *deviceMotion, NSError *error) {

            gyroStr = [NSString stringWithFormat:@"%@\nX=%f Y=%f Z=%f  Attitude.roll=%f Attitude.pitch=%f Attitude.yaw=%f: %@"
                       , gyroStr
                       , deviceMotion.userAcceleration.x
                       , deviceMotion.userAcceleration.y
                       , deviceMotion.userAcceleration.z
                       , deviceMotion.attitude.roll
                       , deviceMotion.attitude.pitch
                       , deviceMotion.attitude.yaw
                       , TimeStamp];//[self getLocalDate] //deviceMotion.timestamp
            
            curDeviceMotion = deviceMotion;

            //-------
            if (isStarted) {
                RedPosition redPos = [self getPositionWithDeviceMotion:deviceMotion];
                
                double rw = redDotView.frame.size.width / 2;

                static NSInteger keepNum = 0; // keep number of cener position of Red Dot View; For keeping 500 ms
                static NSInteger poseNum = 0; // it will have 12 poses
                
//                [self moveRedDotViewToX:x andY:y];
                
                if (fabs(redPos.x) < rw && fabs(redPos.y) < rw) {
                    [self moveRedDotViewToX:0 andY:0];
                    keepNum ++;
                    if (keepNum >= totalKeep) {
                        keepNum = 0;
                        poseNum ++;

                        if (poseNum <= POSENUM){

                            isStarted = NO;
                            [self showRecordingImage];

                            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC);
                            dispatch_after(popTime, dispatch_get_main_queue(), ^{
                               [self getPanoImagesWithIndex:poseNum];
                                if (poseNum == POSENUM) {
                                    poseNum = 0;
                                }
                            });
    //                            [self moveBasePosToNext];
                        }
                        
                    }
                }else{
                    [self moveRedDotViewToX: - redPos.x andY:redPos.y];
                    keepNum ++;
                }
                
//                RedPosition curPos = [self getVirtualPosition:deviceMotion];
//                CGFloat rw = redDotView.frame.size.width / 2;
//                
//                static NSInteger keepNum = 0; // keep number of cener position of Red Dot View; For keeping 500 ms
//                static NSInteger poseNum = 0; // it will have 12 poses
//                
//                if (rw > fabs(curPos.x) && rw > fabs(curPos.y)) { // Near to Center
//                    [self moveRedDotViewToX:0 andY:0];
//                    keepNum ++;
//                    if (keepNum >= totalKeep) {
//                        keepNum = 0;
//                        poseNum ++;
//                        
//                        if (poseNum < 13){
//                            
//                            isStarted = NO;
//                            [self showRecordingImage];
//                            
//                            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC);
//                            dispatch_after(popTime, dispatch_get_main_queue(), ^{
//                               [self getPanoImagesWithIndex:poseNum];
//                                if (poseNum >= 12) {
//                                    poseNum = 0;
//                                }
//                            });
////                            [self moveBasePosToNext];
//                        }
//                        
//                    }
//                }else{
//                    [self moveRedDotViewToX:curPos.x andY:curPos.y];
//                    keepNum ++;
//                }
//                NSLog(@"X = %f, Y = %f", curPos.x, curPos.y);
            }
        }];
    }
    
}

- (void)stopUpdates
{
    CMMotionManager *mManager = [(AppDelegate *)[[UIApplication sharedApplication] delegate] sharedManager];
    
    if ([mManager isAccelerometerActive] == YES) {
        [mManager stopAccelerometerUpdates];
    }
    if ([mManager isGyroActive]) {
        [mManager stopGyroUpdates];
    }
    if ([mManager isDeviceMotionActive]) {
        [mManager stopDeviceMotionUpdates];
    }
}


@end
