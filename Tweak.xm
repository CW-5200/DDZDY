#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#define PLUGIN_NAME @"DD全局虚拟定位"
#define PLUGIN_VERSION @"2.0.0"

// MARK: - 设置键名
static NSString * const kGlobalFakeLocationEnabledKey = @"com.dd.global.virtual.location.enabled";
static NSString * const kGlobalFakeLatitudeKey = @"com.dd.global.virtual.location.latitude";
static NSString * const kGlobalFakeLongitudeKey = @"com.dd.global.virtual.location.longitude";
static NSString * const kGlobalFakeAltitudeKey = @"com.dd.global.virtual.location.altitude";
static NSString * const kGlobalFakeAccuracyKey = @"com.dd.global.virtual.location.accuracy";

// MARK: - 位置管理器
@interface DDLocationManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL isLocationSpoofingEnabled;
@property (nonatomic, strong) CLLocation *cachedFakeLocation;
@property (nonatomic, strong) NSDate *lastLocationUpdate;
- (void)loadSettings;
- (void)saveSettings;
- (CLLocation *)getFakeLocation;
- (CLLocation *)createFakeLocation;
@end

@implementation DDLocationManager

+ (instancetype)sharedManager {
    static DDLocationManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DDLocationManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self loadSettings];
    }
    return self;
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _isLocationSpoofingEnabled = [defaults boolForKey:kGlobalFakeLocationEnabledKey];
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:_isLocationSpoofingEnabled forKey:kGlobalFakeLocationEnabledKey];
    [defaults synchronize];
}

- (CLLocation *)getFakeLocation {
    // 检查是否需要刷新缓存的位置
    if (!_cachedFakeLocation || [[NSDate date] timeIntervalSinceDate:_lastLocationUpdate] > 1.0) {
        _cachedFakeLocation = [self createFakeLocation];
        _lastLocationUpdate = [NSDate date];
    }
    return _cachedFakeLocation;
}

- (CLLocation *)createFakeLocation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double latitude = [defaults doubleForKey:kGlobalFakeLatitudeKey];
    double longitude = [defaults doubleForKey:kGlobalFakeLongitudeKey];
    double altitude = [defaults doubleForKey:kGlobalFakeAltitudeKey];
    double accuracy = [defaults doubleForKey:kGlobalFakeAccuracyKey] ?: 5.0;
    
    // 如果坐标无效，使用默认值
    if (latitude == 0 && longitude == 0) {
        latitude = 39.9035;
        longitude = 116.3976;
    }
    
    // 添加轻微随机抖动，提高真实性
    double latOffset = ((double)arc4random() / UINT32_MAX - 0.5) * 0.00001;
    double lngOffset = ((double)arc4random() / UINT32_MAX - 0.5) * 0.00001;
    double accuracyJitter = ((double)arc4random() / UINT32_MAX) * 2.0;
    
    return [[CLLocation alloc] 
            initWithCoordinate:CLLocationCoordinate2DMake(latitude + latOffset, longitude + lngOffset)
            altitude:altitude
            horizontalAccuracy:accuracy + accuracyJitter
            verticalAccuracy:accuracy + accuracyJitter
            timestamp:[NSDate date]];
}

@end

// MARK: - 地图选择视图控制器
@interface GlobalLocationMapViewController : UIViewController <UISearchBarDelegate, MKMapViewDelegate>
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) CLGeocoder *geocoder;
@property (copy, nonatomic) void (^completionHandler)(CLLocationCoordinate2D coordinate);
@end

@implementation GlobalLocationMapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"选择全局位置";
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
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double latitude = [defaults doubleForKey:kGlobalFakeLatitudeKey] ?: 39.9035;
    double longitude = [defaults doubleForKey:kGlobalFakeLongitudeKey] ?: 116.3976;
    
    CLLocationCoordinate2D initialCoord = CLLocationCoordinate2DMake(latitude, longitude);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(initialCoord, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
    
    MKPointAnnotation *existingAnnotation = [[MKPointAnnotation alloc] init];
    existingAnnotation.coordinate = initialCoord;
    existingAnnotation.title = @"当前虚拟位置";
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
                annotation.subtitle = [NSString stringWithFormat:@"%.4f, %.4f", coordinate.latitude, coordinate.longitude];
                self.searchBar.text = [NSString stringWithFormat:@"%.4f, %.4f", coordinate.latitude, coordinate.longitude];
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
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setDouble:coordinate.latitude forKey:kGlobalFakeLatitudeKey];
        [defaults setDouble:coordinate.longitude forKey:kGlobalFakeLongitudeKey];
        [defaults synchronize];
        
        // 重置位置缓存
        [[DDLocationManager sharedManager] setCachedFakeLocation:nil];
        
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        
        if (self.completionHandler) {
            self.completionHandler(coordinate);
        }
        
        [self.navigationController dismissViewControllerAnimated:YES completion:^{
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                CFSTR("com.dd.global.virtual.location.settings_changed"),
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
    
    if ([annotation.title isEqualToString:@"当前虚拟位置"]) {
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
        self.searchBar.text = [NSString stringWithFormat:@"%.4f, %.4f", annotation.coordinate.latitude, annotation.coordinate.longitude];
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
@interface DDGlobalVirtualLocationSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation DDGlobalVirtualLocationSettingsViewController

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
        return [[DDLocationManager sharedManager] isLocationSpoofingEnabled] ? 1 : 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"全局虚拟定位开关";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"开启后，所有App将使用您设置的虚拟位置信息";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (indexPath.section == 0) {
        NSString *cellIdentifier = @"SwitchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        }
        
        cell.textLabel.text = @"启用全局虚拟定位";
        
        UISwitch *switchView = [[UISwitch alloc] init];
        switchView.onTintColor = [UIColor systemBlueColor];
        switchView.on = [[DDLocationManager sharedManager] isLocationSpoofingEnabled];
        [switchView addTarget:self action:@selector(globalFakeLocationEnabledChanged:) forControlEvents:UIControlEventValueChanged];
        
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
        
        double latitude = [defaults doubleForKey:kGlobalFakeLatitudeKey];
        double longitude = [defaults doubleForKey:kGlobalFakeLongitudeKey];
        
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = @"打开地图自定义";
        content.secondaryText = [NSString stringWithFormat:@"当前：%.4f, %.4f", latitude, longitude];
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
    GlobalLocationMapViewController *mapVC = [[GlobalLocationMapViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:mapVC];
    
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.sheetPresentationController.preferredCornerRadius = 16;
    
    if (@available(iOS 16.0, *)) {
        nav.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    
    __weak typeof(self) weakSelf = self;
    mapVC.completionHandler = ^(CLLocationCoordinate2D coordinate) {
        [weakSelf.tableView reloadData];
    };
    
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)globalFakeLocationEnabledChanged:(UISwitch *)sender {
    [[DDLocationManager sharedManager] setIsLocationSpoofingEnabled:sender.isOn];
    [[DDLocationManager sharedManager] saveSettings];
    
    // 重置位置缓存
    [[DDLocationManager sharedManager] setCachedFakeLocation:nil];
    
    [self.tableView reloadData];
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        CFSTR("com.dd.global.virtual.location.settings_changed"),
                                        NULL,
                                        NULL,
                                        YES);
}

@end

// MARK: - 定时器管理函数
static void setupFakeLocationTimerForManager(CLLocationManager *manager) {
    // 停止可能存在的旧定时器
    dispatch_source_t oldTimer = objc_getAssociatedObject(manager, "fakeLocationTimer");
    if (oldTimer) {
        dispatch_source_cancel(oldTimer);
    }

    // 创建新定时器
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                           dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC),
                           1.0 * NSEC_PER_SEC,  // 每1秒更新一次
                           0.1 * NSEC_PER_SEC);

    __weak CLLocationManager *weakManager = manager;
    dispatch_source_set_event_handler(timer, ^{
        __strong CLLocationManager *strongManager = weakManager;
        if (strongManager && [[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
            CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];

            if (strongManager.delegate && [strongManager.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [strongManager.delegate locationManager:strongManager didUpdateLocations:@[fakeLocation]];
            }
        }
    });

    dispatch_resume(timer);
    // 将定时器关联到manager对象
    objc_setAssociatedObject(manager, "fakeLocationTimer", timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// MARK: - Hook实现
%hook CLLocationManager

// 关键：拦截位置更新方法
- (void)locationManager:(id)arg1 didUpdateLocations:(NSArray *)arg2 {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        %orig(arg1, @[fakeLocation]);
    } else {
        %orig(arg1, arg2);
    }
}

// 关键：拦截startUpdatingLocation
- (void)startUpdatingLocation {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        // 先立即发送一次位置更新
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];

        if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
        }

        // 设置定时器持续发送位置更新 - 使用外部函数
        setupFakeLocationTimerForManager(self);
    } else {
        %orig;
    }
}

// 关键：拦截stopUpdatingLocation
- (void)stopUpdatingLocation {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        // 停止定时器
        dispatch_source_t timer = objc_getAssociatedObject(self, "fakeLocationTimer");
        if (timer) {
            dispatch_source_cancel(timer);
            objc_setAssociatedObject(self, "fakeLocationTimer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else {
        %orig;
    }
}

// 关键：拦截位置属性
- (CLLocation *)location {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        return [[DDLocationManager sharedManager] getFakeLocation];
    }
    return %orig;
}

// 模拟定位服务开启状态
- (BOOL)locationServicesEnabled {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        return YES;
    }
    return %orig;
}

// 模拟授权状态
- (CLAuthorizationStatus)authorizationStatus {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// 关键：Hook CLLocation的属性
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.coordinate;
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.horizontalAccuracy;
    }
    return %orig;
}

- (CLLocationAccuracy)verticalAccuracy {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.verticalAccuracy;
    }
    return %orig;
}

- (CLLocationDistance)altitude {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.altitude;
    }
    return %orig;
}

- (CLLocationSpeed)speed {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.speed;
    }
    return %orig;
}

- (CLLocationDirection)course {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.course;
    }
    return %orig;
}

- (NSDate *)timestamp {
    if ([[DDLocationManager sharedManager] isLocationSpoofingEnabled]) {
        CLLocation *fakeLocation = [[DDLocationManager sharedManager] getFakeLocation];
        return fakeLocation.timestamp;
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
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // 设置默认值
        if (![defaults objectForKey:kGlobalFakeLocationEnabledKey]) {
            [defaults setBool:NO forKey:kGlobalFakeLocationEnabledKey];
        }
        
        if ([defaults doubleForKey:kGlobalFakeLatitudeKey] == 0 && [defaults doubleForKey:kGlobalFakeLongitudeKey] == 0) {
            [defaults setDouble:39.9035 forKey:kGlobalFakeLatitudeKey];
            [defaults setDouble:116.3976 forKey:kGlobalFakeLongitudeKey];
            [defaults setDouble:50.0 forKey:kGlobalFakeAltitudeKey];
            [defaults setDouble:5.0 forKey:kGlobalFakeAccuracyKey];
            [defaults synchronize];
        }
        
        // 初始化位置管理器
        [DDLocationManager sharedManager];
        
        // 注册插件到微信插件管理器
        Class pluginsMgrClass = NSClassFromString(@"WCPluginsMgr");
        if (pluginsMgrClass && [pluginsMgrClass respondsToSelector:@selector(sharedInstance)]) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] registerControllerWithTitle:PLUGIN_NAME 
                                                                               version:PLUGIN_VERSION 
                                                                           controller:@"DDGlobalVirtualLocationSettingsViewController"];
        }
        
        NSLog(@"[DDGPS] 全局虚拟定位插件已加载 (iOS 15.0+)");
    }
}