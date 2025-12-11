#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#define PLUGIN_NAME @"DD虚拟定位"
#define PLUGIN_VERSION @"1.0.4"

// MARK: - 设置键名
static NSString * const kLocationSpoofingEnabledKey = @"LocationSpoofingEnabled";
static NSString * const kLatitudeKey = @"latitude";
static NSString * const kLongitudeKey = @"longitude";

// MARK: - 插件管理器接口声明
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
- (void)registerSwitchWithTitle:(NSString *)title key:(NSString *)key;
@end

// MARK: - 全局位置管理器
@interface WeChatLocationManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;

@property (nonatomic, strong) dispatch_source_t locationUpdateTimer;
@property (nonatomic, assign) BOOL isTimerActive;

@property (nonatomic, assign) BOOL temporarilyDisabled;
@property (nonatomic, assign) BOOL originalEnabledState;

- (CLLocation *)getCurrentFakeLocation;
- (void)setLocationWithLatitude:(double)lat longitude:(double)lng;
- (void)loadSettings;
- (void)startFakeLocationUpdatesForManager:(CLLocationManager *)manager;
- (void)stopFakeLocationUpdates;

- (void)enableTemporaryDisable;
- (void)disableTemporaryDisable;
- (BOOL)isVirtualLocationEnabled;
@end

@implementation WeChatLocationManager

+ (instancetype)sharedManager {
    static WeChatLocationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WeChatLocationManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _temporarilyDisabled = NO;
        _originalEnabledState = NO;
        _isTimerActive = NO;
        [self loadSettings];
    }
    return self;
}

- (void)dealloc {
    [self stopFakeLocationUpdates];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _isEnabled = [defaults boolForKey:kLocationSpoofingEnabledKey];
    _latitude = [defaults doubleForKey:kLatitudeKey] ?: 39.9042;
    _longitude = [defaults doubleForKey:kLongitudeKey] ?: 116.4074;
    
    NSLog(@"[DDGPS] 加载设置: enabled=%d, lat=%.6f, lng=%.6f", _isEnabled, _latitude, _longitude);
}

- (void)setLocationWithLatitude:(double)lat longitude:(double)lng {
    _latitude = lat;
    _longitude = lng;
    _isEnabled = YES;
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:lat forKey:kLatitudeKey];
    [defaults setDouble:lng forKey:kLongitudeKey];
    [defaults setBool:YES forKey:kLocationSpoofingEnabledKey];
    [defaults synchronize];
    
    NSLog(@"[DDGPS] 位置已设置: %.6f, %.6f", lat, lng);
}

- (CLLocation *)getCurrentFakeLocation {
    if (self.temporarilyDisabled) {
        return nil;
    }
    
    CLLocation *fakeLocation = [[CLLocation alloc]
        initWithCoordinate:CLLocationCoordinate2DMake(_latitude, _longitude)
        altitude:0
        horizontalAccuracy:5.0
        verticalAccuracy:3.0
        course:0.0
        speed:0.0
        timestamp:[NSDate date]];
    
    return fakeLocation;
}

- (void)startFakeLocationUpdatesForManager:(CLLocationManager *)manager {
    if (![self isVirtualLocationEnabled] || _isTimerActive) {
        return;
    }
    
    NSLog(@"[DDGPS] 启动虚拟位置更新定时器");
    _isTimerActive = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CLLocation *fakeLocation = [self getCurrentFakeLocation];
        if (fakeLocation && manager.delegate && [manager.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [manager.delegate locationManager:manager didUpdateLocations:@[fakeLocation]];
        }
    });
    
    _locationUpdateTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_locationUpdateTimer,
                             dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC),
                             1.0 * NSEC_PER_SEC,
                             0.1 * NSEC_PER_SEC);
    
    __weak typeof(self) weakSelf = self;
    __weak typeof(manager) weakManager = manager;
    
    dispatch_source_set_event_handler(_locationUpdateTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakManager) strongManager = weakManager;
        
        if ([strongSelf isVirtualLocationEnabled] && strongSelf.isTimerActive) {
            CLLocation *fakeLocation = [strongSelf getCurrentFakeLocation];
            if (fakeLocation && strongManager.delegate && [strongManager.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [strongManager.delegate locationManager:strongManager didUpdateLocations:@[fakeLocation]];
            }
        } else {
            [strongSelf stopFakeLocationUpdates];
        }
    });
    
    dispatch_resume(_locationUpdateTimer);
}

- (void)stopFakeLocationUpdates {
    if (_locationUpdateTimer) {
        if (_isTimerActive) {
            NSLog(@"[DDGPS] 停止虚拟位置更新定时器");
            dispatch_source_cancel(_locationUpdateTimer);
        }
        _locationUpdateTimer = nil;
        _isTimerActive = NO;
    }
}

- (void)enableTemporaryDisable {
    if (!self.temporarilyDisabled) {
        self.originalEnabledState = self.isEnabled;
        self.temporarilyDisabled = YES;
        NSLog(@"[DDGPS] 已临时禁用虚拟定位，原始状态: %d", self.originalEnabledState);
    }
}

- (void)disableTemporaryDisable {
    if (self.temporarilyDisabled) {
        self.temporarilyDisabled = NO;
        NSLog(@"[DDGPS] 已恢复虚拟定位，恢复状态: %d", self.originalEnabledState);
    }
}

- (BOOL)isVirtualLocationEnabled {
    return !self.temporarilyDisabled && self.isEnabled;
}

@end

// MARK: - 地图选择视图控制器
@interface LocationMapViewController : UIViewController <UISearchBarDelegate, MKMapViewDelegate, CLLocationManagerDelegate>
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) CLGeocoder *geocoder;
@property (copy, nonatomic) void (^completionHandler)(CLLocationCoordinate2D coordinate);

@property (strong, nonatomic) CLLocationManager *locationManager;
@property (assign, nonatomic) BOOL isUsingRealLocation;
@property (assign, nonatomic) BOOL isFollowingUserLocation;
@property (strong, nonatomic) UIButton *locateMeButton;
@end

@implementation LocationMapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"选择位置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [[WeChatLocationManager sharedManager] enableTemporaryDisable];
    
    [self setupNavigationBar];
    [self setupUI];
    [self setupMap];
    [self setupLocationButton];
    
    self.geocoder = [[CLGeocoder alloc] init];
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.isUsingRealLocation = NO;
    self.isFollowingUserLocation = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[WeChatLocationManager sharedManager] disableTemporaryDisable];
    
    if (self.isUsingRealLocation) {
        [self.locationManager stopUpdatingLocation];
        self.isUsingRealLocation = NO;
        self.mapView.showsUserLocation = NO;
        self.isFollowingUserLocation = NO;
    }
}

- (void)dealloc {
    [[WeChatLocationManager sharedManager] disableTemporaryDisable];
}

- (void)setupNavigationBar {
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStyleDone target:self action:@selector(closeMapSelection)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    
    UIBarButtonItem *confirmButton = [[UIBarButtonItem alloc] initWithTitle:@"确认" style:UIBarButtonItemStyleDone target:self action:@selector(confirmMapSelection)];
    self.navigationItem.rightBarButtonItem = confirmButton;
    
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor systemBackgroundColor];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: [UIColor labelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
    };
    
    appearance.shadowColor = [UIColor clearColor];
    appearance.shadowImage = [[UIImage alloc] init];
    
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
}

- (void)setupUI {
    UIView *searchContainer = [[UIView alloc] init];
    searchContainer.backgroundColor = [UIColor clearColor];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.layer.cornerRadius = 12;
    blurView.layer.masksToBounds = YES;
    
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地点或输入坐标（格式：纬度,经度）";
    self.searchBar.searchBarStyle = UISearchBarStyleDefault;
    self.searchBar.barTintColor = [UIColor clearColor];
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    
    UITextField *searchTextField = self.searchBar.searchTextField;
    searchTextField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    searchTextField.layer.cornerRadius = 10;
    searchTextField.layer.masksToBounds = YES;
    searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    
    [blurView.contentView addSubview:self.searchBar];
    [searchContainer addSubview:blurView];
    [self.view addSubview:searchContainer];
    
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"长按地图可选择位置";
    hintLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.textColor = [UIColor secondaryLabelColor];
    hintLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:hintLabel];
    
    searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [searchContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [searchContainer.heightAnchor constraintEqualToConstant:52],
        [blurView.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor],
        [blurView.topAnchor constraintEqualToAnchor:searchContainer.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:blurView.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:blurView.trailingAnchor],
        [self.searchBar.topAnchor constraintEqualToAnchor:blurView.topAnchor],
        [self.searchBar.bottomAnchor constraintEqualToAnchor:blurView.bottomAnchor],
        [hintLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [hintLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hintLabel.heightAnchor constraintEqualToConstant:20]
    ]];
}

- (void)setupMap {
    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    
    self.mapView.showsUserLocation = NO;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.pointOfInterestFilter = [MKPointOfInterestFilter filterIncludingAllCategories];
    self.mapView.layer.cornerRadius = 12;
    self.mapView.layer.masksToBounds = YES;
    
    [self.view addSubview:self.mapView];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 修复地图约束，确保用户位置能够居中显示
    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:16],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-40]
    ]];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    [self.mapView addGestureRecognizer:longPress];
    
    CLLocationCoordinate2D initialCoord = CLLocationCoordinate2DMake([WeChatLocationManager sharedManager].latitude, 
                                                                     [WeChatLocationManager sharedManager].longitude);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(initialCoord, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
    
    MKPointAnnotation *existingAnnotation = [[MKPointAnnotation alloc] init];
    existingAnnotation.coordinate = initialCoord;
    existingAnnotation.title = @"虚拟位置";
    [self.mapView addAnnotation:existingAnnotation];
}

- (void)setupLocationButton {
    self.locateMeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.locateMeButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.locateMeButton.backgroundColor = [UIColor systemBackgroundColor];
    self.locateMeButton.tintColor = [UIColor systemBlueColor];
    self.locateMeButton.layer.cornerRadius = 20;
    self.locateMeButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.locateMeButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.locateMeButton.layer.shadowRadius = 3;
    self.locateMeButton.layer.shadowOpacity = 0.2;
    self.locateMeButton.layer.masksToBounds = NO;
    
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    UIImage *locationIcon = [UIImage systemImageNamed:@"location.fill" withConfiguration:config];
    [self.locateMeButton setImage:locationIcon forState:UIControlStateNormal];
    
    [self.locateMeButton addTarget:self action:@selector(centerToCurrentLocation) forControlEvents:UIControlEventTouchUpInside];
    
    [self.mapView addSubview:self.locateMeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.locateMeButton.trailingAnchor constraintEqualToAnchor:self.mapView.trailingAnchor constant:-20],
        [self.locateMeButton.bottomAnchor constraintEqualToAnchor:self.mapView.bottomAnchor constant:-20],
        [self.locateMeButton.widthAnchor constraintEqualToConstant:40],
        [self.locateMeButton.heightAnchor constraintEqualToConstant:40]
    ]];
}

- (void)closeMapSelection {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)centerToCurrentLocation {
    CLAuthorizationStatus status = [self.locationManager authorizationStatus];
    
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
               status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager startUpdatingLocation];
        self.isUsingRealLocation = YES;
        self.mapView.showsUserLocation = YES;
        self.isFollowingUserLocation = YES;
        
        self.locateMeButton.enabled = NO;
        self.locateMeButton.alpha = 0.7;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.locateMeButton.enabled = YES;
            self.locateMeButton.alpha = 1.0;
        });
    } else {
        [self showAlertWithTitle:@"定位权限" message:@"请前往设置-隐私-定位服务中开启微信的定位权限" showSettingsButton:YES];
    }
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
        
        NSMutableArray *annotationsToRemove = [NSMutableArray array];
        for (id<MKAnnotation> annotation in self.mapView.annotations) {
            if ([annotation.title isEqualToString:@"选择的位置"]) {
                [annotationsToRemove addObject:annotation];
            }
        }
        [self.mapView removeAnnotations:annotationsToRemove];
        
        CGPoint touchPoint = [gesture locationInView:self.mapView];
        CLLocationCoordinate2D coordinate = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
        
        MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
        annotation.coordinate = coordinate;
        annotation.title = @"选择的位置";
        
        CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
        [self.geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            if (!error && placemarks.count > 0) {
                CLPlacemark *placemark = placemarks.firstObject;
                NSString *address = [self formatPlacemarkAddress:placemark];
                annotation.subtitle = address;
                self.searchBar.text = address;
            } else {
                annotation.subtitle = [NSString stringWithFormat:@"%.6f, %.6f", coordinate.latitude, coordinate.longitude];
                self.searchBar.text = [NSString stringWithFormat:@"%.6f, %.6f", coordinate.latitude, coordinate.longitude];
            }
        }];
        
        [self.mapView addAnnotation:annotation];
        
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 500, 500);
        [self.mapView setRegion:region animated:YES];
        [self.mapView selectAnnotation:annotation animated:YES];
        
        self.isFollowingUserLocation = NO;
    }
}

- (NSString *)formatPlacemarkAddress:(CLPlacemark *)placemark {
    NSMutableString *address = [NSMutableString string];
    if (placemark.name) [address appendString:placemark.name];
    if (placemark.locality) {
        if (address.length > 0) [address appendString:@", "];
        [address appendString:placemark.locality];
    }
    if (placemark.administrativeArea && ![placemark.administrativeArea isEqualToString:placemark.locality]) {
        if (address.length > 0) [address appendString:@", "];
        [address appendString:placemark.administrativeArea];
    }
    if (placemark.country) {
        if (address.length > 0) [address appendString:@", "];
        [address appendString:placemark.country];
    }
    return address.length > 0 ? address : @"未知地点";
}

- (void)confirmMapSelection {
    MKPointAnnotation *selectedAnnotation = nil;
    for (id<MKAnnotation> annotation in self.mapView.annotations) {
        if ([annotation.title isEqualToString:@"选择的位置"]) {
            selectedAnnotation = (MKPointAnnotation *)annotation;
            break;
        }
    }
    
    if (selectedAnnotation) {
        CLLocationCoordinate2D coordinate = selectedAnnotation.coordinate;
        
        [[WeChatLocationManager sharedManager] setLocationWithLatitude:coordinate.latitude 
                                                             longitude:coordinate.longitude];
        
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        
        if (self.completionHandler) {
            self.completionHandler(coordinate);
        }
        
        [self.navigationController dismissViewControllerAnimated:YES completion:^{
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                CFSTR("com.dd.virtual.location.settings_changed"),
                                                NULL,
                                                NULL,
                                                YES);
        }];
    } else {
        [self showAlertWithTitle:@"提示" message:@"请先在地图上选择一个位置" showSettingsButton:NO];
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message showSettingsButton:(BOOL)showSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    if (showSettings) {
        [alert addAction:[UIAlertAction actionWithTitle:@"去设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if ([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
                [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
            }
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    } else {
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    
    static NSString *annotationId = @"customAnnotation";
    MKMarkerAnnotationView *markerView = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:annotationId];
    
    if (!markerView) {
        markerView = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:annotationId];
        markerView.canShowCallout = YES;
        markerView.animatesWhenAdded = YES;
        markerView.glyphTintColor = [UIColor whiteColor];
        UIButton *detailButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        markerView.rightCalloutAccessoryView = detailButton;
    } else {
        markerView.annotation = annotation;
    }
    
    if ([annotation.title isEqualToString:@"虚拟位置"]) {
        markerView.markerTintColor = [UIColor systemGreenColor];
        markerView.glyphImage = [UIImage systemImageNamed:@"mappin.circle.fill"];
    } else if ([annotation.title isEqualToString:@"选择的位置"]) {
        markerView.markerTintColor = [UIColor systemBlueColor];
        markerView.glyphImage = [UIImage systemImageNamed:@"mappin"];
    }
    
    return markerView;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    if ([view.annotation isKindOfClass:[MKPointAnnotation class]]) {
        MKPointAnnotation *annotation = (MKPointAnnotation *)view.annotation;
        self.searchBar.text = [NSString stringWithFormat:@"%.6f, %.6f", annotation.coordinate.latitude, annotation.coordinate.longitude];
        [self.searchBar becomeFirstResponder];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    
    NSString *searchText = searchBar.text;
    if (searchText.length == 0) return;
    
    NSArray *components = [searchText componentsSeparatedByString:@","];
    if (components.count == 2) {
        NSString *latStr = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *lngStr = [components[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        double lat = [latStr doubleValue];
        double lng = [lngStr doubleValue];
        
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(lat, lng);
            [self addSelectedAnnotationAtCoordinate:coordinate withSubtitle:searchText];
            return;
        }
    }
    
    [self.geocoder geocodeAddressString:searchText completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error) {
            [self showAlertWithTitle:@"搜索失败" message:@"未找到该地点，请尝试输入坐标格式：纬度,经度" showSettingsButton:NO];
            return;
        }
        
        if (placemarks.count > 0) {
            CLPlacemark *placemark = placemarks.firstObject;
            [self addSelectedAnnotationAtCoordinate:placemark.location.coordinate withSubtitle:[self formatPlacemarkAddress:placemark]];
        }
    }];
}

- (void)addSelectedAnnotationAtCoordinate:(CLLocationCoordinate2D)coordinate withSubtitle:(NSString *)subtitle {
    NSMutableArray *annotationsToRemove = [NSMutableArray array];
    for (id<MKAnnotation> annotation in self.mapView.annotations) {
        if ([annotation.title isEqualToString:@"选择的位置"]) {
            [annotationsToRemove addObject:annotation];
        }
    }
    [self.mapView removeAnnotations:annotationsToRemove];
    
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = coordinate;
    annotation.title = @"选择的位置";
    annotation.subtitle = subtitle;
    [self.mapView addAnnotation:annotation];
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
    [self.mapView selectAnnotation:annotation animated:YES];
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (locations.count > 0 && self.isUsingRealLocation) {
        CLLocation *currentLocation = locations.firstObject;
        
        [manager stopUpdatingLocation];
        self.isUsingRealLocation = NO;
        
        if (self.isFollowingUserLocation) {
            // 创建一个以用户位置为中心的可见区域
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(currentLocation.coordinate, 200, 200);
            
            // 设置地图区域，确保用户位置在地图中心
            [self.mapView setRegion:region animated:YES];
        }
        
        self.locateMeButton.enabled = YES;
        self.locateMeButton.alpha = 1.0;
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        [manager startUpdatingLocation];
        self.isUsingRealLocation = YES;
        self.mapView.showsUserLocation = YES;
        self.isFollowingUserLocation = YES;
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        self.locateMeButton.enabled = YES;
        self.locateMeButton.alpha = 1.0;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (error.code == kCLErrorDenied) {
        [manager stopUpdatingLocation];
        self.isUsingRealLocation = NO;
        self.mapView.showsUserLocation = NO;
        self.isFollowingUserLocation = NO;
        
        self.locateMeButton.enabled = YES;
        self.locateMeButton.alpha = 1.0;
    }
}

#pragma mark - MKMapViewDelegate
- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    if (self.isFollowingUserLocation && animated) {
        self.isFollowingUserLocation = NO;
    }
}

@end

// MARK: - 设置视图控制器
@interface DDVirtualLocationSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation DDVirtualLocationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PLUGIN_NAME;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAutomatic;
    
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor systemBackgroundColor];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: [UIColor labelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
    };
    
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1;
    } else {
        return [WeChatLocationManager sharedManager].isEnabled ? 1 : 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"虚拟定位开关";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"开启后，微信将使用您设置的位置信息";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSString *cellIdentifier = @"SwitchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        }
        
        cell.textLabel.text = @"启用虚拟定位";
        
        UISwitch *switchView = [[UISwitch alloc] init];
        switchView.onTintColor = [UIColor systemBlueColor];
        switchView.on = [WeChatLocationManager sharedManager].isEnabled;
        [switchView addTarget:self action:@selector(fakeLocationEnabledChanged:) forControlEvents:UIControlEventValueChanged];
        
        cell.accessoryView = switchView;
        return cell;
        
    } else {
        NSString *cellIdentifier = @"MapSelectionCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        }
        
        double latitude = [WeChatLocationManager sharedManager].latitude;
        double longitude = [WeChatLocationManager sharedManager].longitude;
        
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = @"打开地图自定义";
        content.secondaryText = [NSString stringWithFormat:@"当前：%.6f, %.6f", latitude, longitude];
        content.textProperties.color = [UIColor labelColor];
        content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
        
        cell.contentConfiguration = content;
        
        return cell;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 55.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1 && indexPath.row == 0) {
        [self showMapSelection];
    }
}

- (void)showMapSelection {
    LocationMapViewController *mapVC = [[LocationMapViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:mapVC];
    
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.sheetPresentationController.preferredCornerRadius = 16;
    
    nav.sheetPresentationController.detents = @[
        [UISheetPresentationControllerDetent mediumDetent],
        [UISheetPresentationControllerDetent largeDetent]
    ];
    nav.sheetPresentationController.prefersGrabberVisible = YES;
    nav.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = NO;
    
    __weak typeof(self) weakSelf = self;
    mapVC.completionHandler = ^(CLLocationCoordinate2D coordinate) {
        [weakSelf.tableView reloadData];
    };
    
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)fakeLocationEnabledChanged:(UISwitch *)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:sender.isOn forKey:kLocationSpoofingEnabledKey];
    [defaults synchronize];
    
    [[WeChatLocationManager sharedManager] loadSettings];
    [self.tableView reloadData];
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        CFSTR("com.dd.virtual.location.settings_changed"),
                                        NULL,
                                        NULL,
                                        YES);
}

@end

// MARK: - Hook CLLocationManager
%hook CLLocationManager

- (void)startUpdatingLocation {
    if ([[WeChatLocationManager sharedManager] isVirtualLocationEnabled]) {
        NSLog(@"[DDGPS] 拦截位置更新请求（虚拟定位启用）");
        [[WeChatLocationManager sharedManager] startFakeLocationUpdatesForManager:self];
    } else {
        NSLog(@"[DDGPS] 允许真实位置更新（虚拟定位临时禁用或未启用）");
        %orig;
    }
}

- (void)stopUpdatingLocation {
    [[WeChatLocationManager sharedManager] stopFakeLocationUpdates];
    %orig;
    NSLog(@"[DDGPS] 停止位置更新");
}

- (CLAuthorizationStatus)authorizationStatus {
    if ([[WeChatLocationManager sharedManager] isVirtualLocationEnabled]) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// MARK: - Hook CLLocation
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if ([[WeChatLocationManager sharedManager] isVirtualLocationEnabled]) {
        return CLLocationCoordinate2DMake(
            [WeChatLocationManager sharedManager].latitude,
            [WeChatLocationManager sharedManager].longitude
        );
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    if ([[WeChatLocationManager sharedManager] isVirtualLocationEnabled]) {
        return 5.0;
    }
    return %orig;
}

%end

// MARK: - 静态回调函数声明
static void loadLocationSettingsCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[WeChatLocationManager sharedManager] loadSettings];
}

// MARK: - 插件初始化
%ctor {
    @autoreleasepool {
        NSLog(@"[DDGPS] 虚拟定位插件已加载 v%@", PLUGIN_VERSION);
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        if (![defaults objectForKey:kLocationSpoofingEnabledKey]) {
            [defaults setBool:NO forKey:kLocationSpoofingEnabledKey];
        }
        
        if ([defaults doubleForKey:kLatitudeKey] == 0 && [defaults doubleForKey:kLongitudeKey] == 0) {
            [defaults setDouble:39.9042 forKey:kLatitudeKey];
            [defaults setDouble:116.4074 forKey:kLongitudeKey];
        }
        
        [defaults synchronize];
        
        [[WeChatLocationManager sharedManager] loadSettings];
        
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        loadLocationSettingsCallback,
                                        CFSTR("com.dd.virtual.location.settings_changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        
        // 注册插件到微信插件管理器
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:PLUGIN_NAME 
                                   version:PLUGIN_VERSION 
                               controller:@"DDVirtualLocationSettingsViewController"];
        }
    }
}
