#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

// MARK: - 插件的配置管理类
@interface DDAssistantConfig : NSObject
+ (instancetype)sharedConfig;

@property (assign, nonatomic) BOOL fakeLocationEnabled;
@property (assign, nonatomic) double fakeLatitude;
@property (assign, nonatomic) double fakeLongitude;
@end

@implementation DDAssistantConfig

static DDAssistantConfig *sharedInstance = nil;
static NSString *const kFakeLocationEnabledKey = @"DDAssistantFakeLocationEnabled";
static NSString *const kFakeLatitudeKey = @"DDAssistantFakeLatitude";
static NSString *const kFakeLongitudeKey = @"DDAssistantFakeLongitude";

+ (instancetype)sharedConfig {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // 位置配置
        _fakeLocationEnabled = [defaults boolForKey:kFakeLocationEnabledKey];
        _fakeLatitude = [defaults doubleForKey:kFakeLatitudeKey];
        _fakeLongitude = [defaults doubleForKey:kFakeLongitudeKey];
        
        // 默认位置设为北京天安门
        if (_fakeLatitude == 0 && _fakeLongitude == 0) {
            _fakeLatitude = 39.9035;
            _fakeLongitude = 116.3976;
            [defaults setDouble:_fakeLatitude forKey:kFakeLatitudeKey];
            [defaults setDouble:_fakeLongitude forKey:kFakeLongitudeKey];
        }
        
        [defaults synchronize];
    }
    return self;
}

#pragma mark - Setter Methods
- (void)setFakeLocationEnabled:(BOOL)fakeLocationEnabled {
    _fakeLocationEnabled = fakeLocationEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:fakeLocationEnabled forKey:kFakeLocationEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setFakeLatitude:(double)fakeLatitude {
    _fakeLatitude = fakeLatitude;
    [[NSUserDefaults standardUserDefaults] setDouble:fakeLatitude forKey:kFakeLatitudeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setFakeLongitude:(double)fakeLongitude {
    _fakeLongitude = fakeLongitude;
    [[NSUserDefaults standardUserDefaults] setDouble:fakeLongitude forKey:kFakeLongitudeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

// MARK: - CLLocationManager钩子
%hook CLLocationManager

- (void)startUpdatingLocation {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        NSLog(@"[DD助手] 位置模拟已启用，拦截位置更新");
        
        // 立即发送一次模拟位置
        [self performSelector:@selector(sendFakeLocation) withObject:nil afterDelay:0.1];
    } else {
        %orig;
    }
}

- (void)stopUpdatingLocation {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (!config.fakeLocationEnabled) {
        %orig;
    }
}

// 发送模拟位置
- (void)sendFakeLocation {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (!config.fakeLocationEnabled) {
        return;
    }
    
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(config.fakeLatitude, config.fakeLongitude);
    
    if (CLLocationCoordinate2DIsValid(coordinate)) {
        CLLocation *fakeLocation = [[CLLocation alloc] 
            initWithCoordinate:coordinate
            altitude:0
            horizontalAccuracy:5.0
            verticalAccuracy:3.0
            course:0
            speed:0
            timestamp:[NSDate date]];
        
        // 安全调用代理方法
        if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
                } @catch (NSException *exception) {
                    NSLog(@"[DD助手] 发送模拟位置失败: %@", exception);
                }
            });
        }
        
        // 设置下一次更新（每秒1次）
        [self performSelector:@selector(sendFakeLocation) withObject:nil afterDelay:1.0];
    }
}

- (BOOL)locationServicesEnabled {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return YES;
    }
    return %orig;
}

- (CLAuthorizationStatus)authorizationStatus {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// MARK: - CLLocation钩子
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        // 检查是否是系统位置对象
        NSString *className = NSStringFromClass([self class]);
        if ([className isEqualToString:@"CLLocation"]) {
            return CLLocationCoordinate2DMake(config.fakeLatitude, config.fakeLongitude);
        }
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return 5.0;
    }
    return %orig;
}

%end

// MARK: - 微信位置相关钩子
%hook MMLocationMgr

- (void)locationManager:(id)arg1 didUpdateToLocation:(id)arg2 fromLocation:(id)arg3 {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:config.fakeLatitude 
                                                              longitude:config.fakeLongitude];
        %orig(arg1, fakeLocation, arg3);
    } else {
        %orig(arg1, arg2, arg3);
    }
}

- (void)locationManager:(id)arg1 didUpdateLocations:(NSArray *)arg2 {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:config.fakeLatitude 
                                                              longitude:config.fakeLongitude];
        %orig(arg1, @[fakeLocation]);
    } else {
        %orig(arg1, arg2);
    }
}

%end

%hook WCLocationInfo

- (double)latitude {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return config.fakeLatitude;
    }
    return %orig;
}

- (double)longitude {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return config.fakeLongitude;
    }
    return %orig;
}

%end

// MARK: - 插件的设置界面
@interface DDAssistantSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, MKMapViewDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) CLGeocoder *geocoder;
@end

@implementation DDAssistantSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"位置设置";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    // 设置导航栏
    [self setupNavigationBar];
    
    // 创建表格
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.sectionHeaderTopPadding = 0;
    
    [self.view addSubview:self.tableView];
    
    // 初始化地理编码器
    self.geocoder = [[CLGeocoder alloc] init];
}

- (void)setupNavigationBar {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImage *backImage = [UIImage systemImageNamed:@"chevron.left" withConfiguration:config];
    
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithImage:backImage
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(backButtonTapped)];
    self.navigationItem.leftBarButtonItem = backButton;
    
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor systemBackgroundColor];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: [UIColor labelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
    };
    appearance.shadowColor = [UIColor separatorColor];
    
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
}

- (void)backButtonTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableView DataSource & Delegate
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    return config.fakeLocationEnabled ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"位置设置";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellIdentifier = @"DDSettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }
    
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (indexPath.row == 0) {
        // 虚拟位置开关
        UISwitch *switchControl = [[UISwitch alloc] init];
        switchControl.onTintColor = [UIColor systemBlueColor];
        switchControl.on = config.fakeLocationEnabled;
        [switchControl addTarget:self action:@selector(fakeLocationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchControl;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
        content.text = @"虚拟位置";
        content.secondaryText = config.fakeLocationEnabled ? 
            [NSString stringWithFormat:@"%.4f, %.4f", config.fakeLatitude, config.fakeLongitude] : 
            @"已关闭";
        content.textProperties.color = [UIColor labelColor];
        content.secondaryTextProperties.color = config.fakeLocationEnabled ? 
            [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
        cell.contentConfiguration = content;
    } else if (indexPath.row == 1) {
        // 地图选择位置
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = @"地图选择位置";
        content.secondaryText = @"点击选择或搜索位置";
        content.textProperties.color = [UIColor labelColor];
        content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
        cell.contentConfiguration = content;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row == 1) {
        [self showMapSelectionView];
    }
}

#pragma mark - Switch Handler
- (void)fakeLocationSwitchChanged:(UISwitch *)sender {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    config.fakeLocationEnabled = sender.on;
    
    // 更新表格
    [self.tableView beginUpdates];
    
    if (sender.on) {
        // 插入地图选择位置行
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    } else {
        // 移除地图选择位置行
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:0];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    }
    
    // 更新开关所在行
    NSIndexPath *switchIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[switchIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    
    [self.tableView endUpdates];
}

#pragma mark - Map Selection
- (void)showMapSelectionView {
    UIViewController *mapVC = [[UIViewController alloc] init];
    mapVC.title = @"选择位置";
    mapVC.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 设置导航栏
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor systemBackgroundColor];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: [UIColor labelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
    };
    appearance.shadowColor = [UIColor separatorColor];
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:mapVC];
    navController.navigationBar.standardAppearance = appearance;
    navController.navigationBar.scrollEdgeAppearance = appearance;
    
    // 取消按钮
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(closeMapSelection)];
    mapVC.navigationItem.leftBarButtonItem = cancelButton;
    
    // 确认按钮
    UIBarButtonItem *confirmButton = [[UIBarButtonItem alloc] initWithTitle:@"确认"
                                                                      style:UIBarButtonItemStyleDone
                                                                     target:self
                                                                     action:@selector(confirmMapSelection)];
    mapVC.navigationItem.rightBarButtonItem = confirmButton;
    
    // 使用SheetPresentationController
    navController.modalPresentationStyle = UIModalPresentationPageSheet;
    navController.sheetPresentationController.preferredCornerRadius = 16;
    navController.sheetPresentationController.detents = @[
        [UISheetPresentationControllerDetent mediumDetent],
        [UISheetPresentationControllerDetent largeDetent]
    ];
    navController.sheetPresentationController.prefersGrabberVisible = YES;
    
    [self presentViewController:navController animated:YES completion:nil];
    
    // 创建地图视图
    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.pointOfInterestFilter = [MKPointOfInterestFilter filterIncludingAllCategories];
    self.mapView.layer.cornerRadius = 12;
    self.mapView.layer.masksToBounds = YES;
    
    // 创建搜索栏
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地点或输入坐标";
    self.searchBar.searchBarStyle = UISearchBarStyleDefault;
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    
    // 设置搜索文本框样式
    UITextField *searchTextField = self.searchBar.searchTextField;
    searchTextField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    searchTextField.layer.cornerRadius = 10;
    searchTextField.layer.masksToBounds = YES;
    searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    
    // 提示标签
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"长按地图选择位置";
    hintLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.textColor = [UIColor secondaryLabelColor];
    
    [mapVC.view addSubview:self.searchBar];
    [mapVC.view addSubview:self.mapView];
    [mapVC.view addSubview:hintLabel];
    
    // AutoLayout
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 搜索栏
        [self.searchBar.topAnchor constraintEqualToAnchor:mapVC.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:mapVC.view.leadingAnchor constant:16],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:mapVC.view.trailingAnchor constant:-16],
        [self.searchBar.heightAnchor constraintEqualToConstant:44],
        
        // 地图
        [self.mapView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:16],
        [self.mapView.leadingAnchor constraintEqualToAnchor:mapVC.view.leadingAnchor constant:16],
        [self.mapView.trailingAnchor constraintEqualToAnchor:mapVC.view.trailingAnchor constant:-16],
        [self.mapView.bottomAnchor constraintEqualToAnchor:hintLabel.topAnchor constant:-12],
        
        // 提示标签
        [hintLabel.bottomAnchor constraintEqualToAnchor:mapVC.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [hintLabel.centerXAnchor constraintEqualToAnchor:mapVC.view.centerXAnchor],
        [hintLabel.heightAnchor constraintEqualToConstant:20]
    ]];
    
    // 添加长按手势
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
                                               initWithTarget:self 
                                               action:@selector(handleMapLongPress:)];
    [self.mapView addGestureRecognizer:longPress];
    
    // 设置初始位置
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    CLLocationCoordinate2D initialCoord = CLLocationCoordinate2DMake(config.fakeLatitude, config.fakeLongitude);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(initialCoord, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
    
    // 添加现有位置标注
    MKPointAnnotation *existingAnnotation = [[MKPointAnnotation alloc] init];
    existingAnnotation.coordinate = initialCoord;
    existingAnnotation.title = @"当前位置";
    [self.mapView addAnnotation:existingAnnotation];
}

- (void)closeMapSelection {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        // 清除之前的选择标注
        for (id<MKAnnotation> annotation in self.mapView.annotations) {
            if ([annotation.title isEqualToString:@"选择的位置"]) {
                [self.mapView removeAnnotation:annotation];
            }
        }
        
        // 获取点击位置
        CGPoint touchPoint = [gesture locationInView:self.mapView];
        CLLocationCoordinate2D coordinate = [self.mapView convertPoint:touchPoint 
                                                  toCoordinateFromView:self.mapView];
        
        // 添加标注
        MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
        annotation.coordinate = coordinate;
        annotation.title = @"选择的位置";
        
        // 地理编码获取地点名称
        CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude 
                                                          longitude:coordinate.longitude];
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
        
        // 聚焦到标注位置
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 500, 500);
        [self.mapView setRegion:region animated:YES];
        
        // 选中标注
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
    // 找到选择的位置标注
    MKPointAnnotation *selectedAnnotation = nil;
    for (id<MKAnnotation> annotation in self.mapView.annotations) {
        if ([annotation.title isEqualToString:@"选择的位置"]) {
            selectedAnnotation = (MKPointAnnotation *)annotation;
            break;
        }
    }
    
    if (selectedAnnotation) {
        CLLocationCoordinate2D coordinate = selectedAnnotation.coordinate;
        
        DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
        config.fakeLatitude = coordinate.latitude;
        config.fakeLongitude = coordinate.longitude;
        
        [self dismissViewControllerAnimated:YES completion:^{
            // 更新表格
            [self.tableView reloadData];
        }];
    }
}

#pragma mark - UISearchBarDelegate
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    
    NSString *searchText = searchBar.text;
    if (searchText.length == 0) return;
    
    // 检查是否是坐标格式
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
    
    // 地理编码搜索
    [self.geocoder geocodeAddressString:searchText completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (placemarks.count > 0) {
            CLPlacemark *placemark = placemarks.firstObject;
            [self addSelectedAnnotationAtCoordinate:placemark.location.coordinate withSubtitle:[self formatPlacemarkAddress:placemark]];
        }
    }];
}

- (void)addSelectedAnnotationAtCoordinate:(CLLocationCoordinate2D)coordinate withSubtitle:(NSString *)subtitle {
    // 清除之前的选择标注
    for (id<MKAnnotation> annotation in self.mapView.annotations) {
        if ([annotation.title isEqualToString:@"选择的位置"]) {
            [self.mapView removeAnnotation:annotation];
        }
    }
    
    // 添加新的标注
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = coordinate;
    annotation.title = @"选择的位置";
    annotation.subtitle = subtitle;
    [self.mapView addAnnotation:annotation];
    
    // 调整地图区域
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
    
    // 选中标注
    [self.mapView selectAnnotation:annotation animated:YES];
}

@end

// MARK: - 插件注册
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

%hook MicroMessengerAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig(application, launchOptions);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class pluginsMgrClass = objc_getClass("WCPluginsMgr");
        if (pluginsMgrClass) {
            id pluginsMgr = [pluginsMgrClass sharedInstance];
            
            if (pluginsMgr && [pluginsMgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [pluginsMgr registerControllerWithTitle:@"位置助手" 
                                               version:@"1.0.0" 
                                            controller:@"DDAssistantSettingsController"];
                
                NSLog(@"[位置助手] 插件注册成功");
            }
        }
    });
    
    return result;
}

%end

%ctor {
    NSLog(@"[位置助手] 插件已加载");
}