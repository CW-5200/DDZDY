#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#define PLUGIN_NAME @"DD虚拟定位"
#define PLUGIN_VERSION @"1.0.1"

// MARK: - 设置键名（更新为统一格式）
static NSString * const kLocationSpoofingEnabledKey = @"LocationSpoofingEnabled";
static NSString * const kLatitudeKey = @"latitude";
static NSString * const kLongitudeKey = @"longitude";

// MARK: - 全局位置管理器
@interface WeChatLocationManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
- (CLLocation *)getCurrentFakeLocation;
- (void)setLocationWithLatitude:(double)lat longitude:(double)lng;
- (void)loadSettings;
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
        [self loadSettings];
    }
    return self;
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
    // 添加微小随机偏移增加真实性
    double latOffset = ((double)arc4random() / UINT32_MAX - 0.5) * 0.0001;
    double lngOffset = ((double)arc4random() / UINT32_MAX - 0.5) * 0.0001;
    
    CLLocation *fakeLocation = [[CLLocation alloc]
        initWithCoordinate:CLLocationCoordinate2DMake(_latitude + latOffset, _longitude + lngOffset)
        altitude:0
        horizontalAccuracy:5.0
        verticalAccuracy:3.0
        course:0.0
        speed:0.0
        timestamp:[NSDate date]];
    
    return fakeLocation;
}

@end

// MARK: - 地图选择视图控制器（保持不变）
@interface LocationMapViewController : UIViewController <UISearchBarDelegate, MKMapViewDelegate>
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) CLGeocoder *geocoder;
@property (copy, nonatomic) void (^completionHandler)(CLLocationCoordinate2D coordinate);
@end

@implementation LocationMapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"选择位置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupNavigationBar];
    [self setupUI];
    [self setupMap];
    
    self.geocoder = [[CLGeocoder alloc] init];
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
    self.searchBar.placeholder = @"搜索地点或输入坐标";
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
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.pointOfInterestFilter = [MKPointOfInterestFilter filterIncludingAllCategories];
    self.mapView.layer.cornerRadius = 12;
    self.mapView.layer.masksToBounds = YES;
    
    [self.view addSubview:self.mapView];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:16],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
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
    existingAnnotation.title = @"当前位置";
    [self.mapView addAnnotation:existingAnnotation];
}

- (void)closeMapSelection {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
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
        [self showAlertWithTitle:@"提示" message:@"请先在地图上选择一个位置"];
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
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
    
    if ([annotation.title isEqualToString:@"当前位置"]) {
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
            [self showAlertWithTitle:@"搜索失败" message:@"未找到该地点，请尝试输入坐标格式：纬度,经度"];
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
    
    // iOS15+ 模态样式
    if (@available(iOS 15.0, *)) {
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
    }
    
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
    
    if (@available(iOS 16.0, *)) {
        nav.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
        nav.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }
    
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

// MARK: - 静态回调函数声明
static void loadLocationSettingsCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[WeChatLocationManager sharedManager] loadSettings];
}

// MARK: - Hook CLLocationManager（修复弃用API问题）
%hook CLLocationManager

- (void)startUpdatingLocation {
    if ([WeChatLocationManager sharedManager].isEnabled) {
        NSLog(@"[DDGPS] 拦截位置更新请求");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CLLocation *fakeLocation = [[WeChatLocationManager sharedManager] getCurrentFakeLocation];
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
            }
            
            // 只使用新的API，移除弃用的API调用
            // 旧API locationManager:didUpdateToLocation:fromLocation: 在iOS 6.0后已废弃
        });
        
        // 设置定时器持续发送虚拟位置
        static dispatch_source_t locationTimer;
        if (locationTimer) {
            dispatch_source_cancel(locationTimer);
        }
        
        locationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(locationTimer,
                                 dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC),
                                 1.0 * NSEC_PER_SEC,
                                 0.1 * NSEC_PER_SEC);
        
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(locationTimer, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if ([WeChatLocationManager sharedManager].isEnabled) {
                CLLocation *fakeLocation = [[WeChatLocationManager sharedManager] getCurrentFakeLocation];
                
                if (strongSelf.delegate && [strongSelf.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                    [strongSelf.delegate locationManager:strongSelf didUpdateLocations:@[fakeLocation]];
                }
            }
        });
        
        dispatch_resume(locationTimer);
    } else {
        %orig;
    }
}

- (void)stopUpdatingLocation {
    if (![WeChatLocationManager sharedManager].isEnabled) {
        %orig;
    }
    NSLog(@"[DDGPS] 停止位置更新");
}

- (CLAuthorizationStatus)authorizationStatus {
    if ([WeChatLocationManager sharedManager].isEnabled) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// MARK: - Hook CLLocation（补充位置信息）
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if ([WeChatLocationManager sharedManager].isEnabled) {
        return CLLocationCoordinate2DMake(
            [WeChatLocationManager sharedManager].latitude,
            [WeChatLocationManager sharedManager].longitude
        );
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    if ([WeChatLocationManager sharedManager].isEnabled) {
        return 5.0;
    }
    return %orig;
}

%end

// MARK: - 插件管理器注册
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

%ctor {
    @autoreleasepool {
        NSLog(@"[DDGPS] 虚拟定位插件已加载 v%@", PLUGIN_VERSION);
        
        // 初始化默认设置
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
        
        // 监听设置变化 - 使用静态函数而不是block
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        loadLocationSettingsCallback,
                                        CFSTR("com.dd.virtual.location.settings_changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        
        // 注册插件到微信插件管理器
        Class pluginsMgrClass = NSClassFromString(@"WCPluginsMgr");
        if (pluginsMgrClass && [pluginsMgrClass respondsToSelector:@selector(sharedInstance)]) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] registerControllerWithTitle:PLUGIN_NAME 
                                                                               version:PLUGIN_VERSION 
                                                                           controller:@"DDVirtualLocationSettingsViewController"];
        }
    }
}