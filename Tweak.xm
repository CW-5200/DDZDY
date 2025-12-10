#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <substrate.h>

#define PLUGIN_NAME @"DD全局虚拟定位"
#define PLUGIN_VERSION @"2.0.0"

// MARK: - 全局变量
static CLLocationCoordinate2D g_fakeLocation = {
    .latitude = 39.9042,   // 北京天安门默认坐标
    .longitude = 116.4074
};
static BOOL g_isLocationSpoofingEnabled = NO;

// MARK: - 设置键名
static NSString * const kGlobalFakeLocationEnabledKey = @"com.dd.global.virtual.location.enabled";
static NSString * const kGlobalFakeLatitudeKey = @"com.dd.global.virtual.location.latitude";
static NSString * const kGlobalFakeLongitudeKey = @"com.dd.global.virtual.location.longitude";

// MARK: - 工具函数
static void loadLocationSettings() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    g_isLocationSpoofingEnabled = [defaults boolForKey:kGlobalFakeLocationEnabledKey];
    double latitude = [defaults doubleForKey:kGlobalFakeLatitudeKey];
    double longitude = [defaults doubleForKey:kGlobalFakeLongitudeKey];
    
    if (latitude != 0 || longitude != 0) {
        g_fakeLocation.latitude = latitude;
        g_fakeLocation.longitude = longitude;
    }
    
    NSLog(@"[DDGPS] 加载设置: enabled=%d, location=%.6f,%.6f", 
          g_isLocationSpoofingEnabled, g_fakeLocation.latitude, g_fakeLocation.longitude);
}

static void saveLocationSettings() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:g_isLocationSpoofingEnabled forKey:kGlobalFakeLocationEnabledKey];
    [defaults setDouble:g_fakeLocation.latitude forKey:kGlobalFakeLatitudeKey];
    [defaults setDouble:g_fakeLocation.longitude forKey:kGlobalFakeLongitudeKey];
    [defaults synchronize];
}

// MARK: - Hook CLLocationManager
%hook CLLocationManager

// 拦截位置更新方法
- (void)locationManager:(id)arg1 didUpdateLocations:(NSArray *)arg2 {
    if (g_isLocationSpoofingEnabled) {
        CLLocation *fakeLocation = [[CLLocation alloc] 
                                   initWithLatitude:g_fakeLocation.latitude 
                                   longitude:g_fakeLocation.longitude];
        NSLog(@"[DDGPS] 发送虚拟位置更新: %.6f, %.6f", g_fakeLocation.latitude, g_fakeLocation.longitude);
        %orig(arg1, @[fakeLocation]);
    } else {
        %orig(arg1, arg2);
    }
}

// 拦截位置属性
- (CLLocation *)location {
    if (g_isLocationSpoofingEnabled) {
        NSLog(@"[DDGPS] 返回虚拟位置: %.6f, %.6f", g_fakeLocation.latitude, g_fakeLocation.longitude);
        return [[CLLocation alloc] initWithLatitude:g_fakeLocation.latitude 
                                          longitude:g_fakeLocation.longitude];
    }
    return %orig;
}

// 拦截startUpdatingLocation
- (void)startUpdatingLocation {
    NSLog(@"[DDGPS] 位置更新已启动");
    if (g_isLocationSpoofingEnabled) {
        // 如果启用了虚拟定位，立即发送一次位置更新
        if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            CLLocation *fakeLocation = [[CLLocation alloc] 
                                       initWithLatitude:g_fakeLocation.latitude 
                                       longitude:g_fakeLocation.longitude];
            [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
        }
    } else {
        %orig;
    }
}

// 模拟定位服务状态
- (BOOL)locationServicesEnabled {
    if (g_isLocationSpoofingEnabled) {
        return YES;
    }
    return %orig;
}

// 模拟授权状态
- (CLAuthorizationStatus)authorizationStatus {
    if (g_isLocationSpoofingEnabled) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// MARK: - Hook CLLocation
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if (g_isLocationSpoofingEnabled) {
        return g_fakeLocation;
    }
    return %orig;
}

- (CLLocationDegrees)latitude {
    if (g_isLocationSpoofingEnabled) {
        return g_fakeLocation.latitude;
    }
    return %orig;
}

- (CLLocationDegrees)longitude {
    if (g_isLocationSpoofingEnabled) {
        return g_fakeLocation.longitude;
    }
    return %orig;
}

%end

// MARK: - 地图选择视图控制器（简化版）
@interface SimpleLocationMapViewController : UIViewController <MKMapViewDelegate>
@property (strong, nonatomic) MKMapView *mapView;
@property (copy, nonatomic) void (^completionHandler)(CLLocationCoordinate2D coordinate);
@end

@implementation SimpleLocationMapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"选择位置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 导航栏按钮
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStyleDone target:self action:@selector(closeMapSelection)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    
    UIBarButtonItem *confirmButton = [[UIBarButtonItem alloc] initWithTitle:@"确定" style:UIBarButtonItemStyleDone target:self action:@selector(confirmMapSelection)];
    self.navigationItem.rightBarButtonItem = confirmButton;
    
    // 地图视图
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.mapView];
    
    // 显示当前位置
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(g_fakeLocation, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
    
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = g_fakeLocation;
    annotation.title = @"当前位置";
    [self.mapView addAnnotation:annotation];
    
    // 长按手势选择位置
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    [self.mapView addGestureRecognizer:longPress];
}

- (void)closeMapSelection {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        // 移除旧标记
        [self.mapView removeAnnotations:self.mapView.annotations];
        
        CGPoint touchPoint = [gesture locationInView:self.mapView];
        CLLocationCoordinate2D coordinate = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
        
        MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
        annotation.coordinate = coordinate;
        annotation.title = @"选择的位置";
        annotation.subtitle = [NSString stringWithFormat:@"%.6f, %.6f", coordinate.latitude, coordinate.longitude];
        [self.mapView addAnnotation:annotation];
        
        [self.mapView selectAnnotation:annotation animated:YES];
    }
}

- (void)confirmMapSelection {
    if (self.mapView.annotations.count > 0) {
        MKPointAnnotation *annotation = self.mapView.annotations.firstObject;
        if (self.completionHandler) {
            self.completionHandler(annotation.coordinate);
        }
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    
    static NSString *annotationId = @"customAnnotation";
    MKMarkerAnnotationView *markerView = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:annotationId];
    
    if (!markerView) {
        markerView = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:annotationId];
        markerView.canShowCallout = YES;
    } else {
        markerView.annotation = annotation;
    }
    
    markerView.markerTintColor = [UIColor systemBlueColor];
    
    return markerView;
}

@end

// MARK: - 设置视图控制器（简化版）
@interface SimpleSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SimpleSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PLUGIN_NAME;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
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
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SwitchCell"];
        cell.textLabel.text = @"启用虚拟定位";
        
        UISwitch *switchView = [[UISwitch alloc] init];
        switchView.onTintColor = [UIColor systemBlueColor];
        switchView.on = g_isLocationSpoofingEnabled;
        [switchView addTarget:self action:@selector(toggleLocationSpoofing:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchView;
        
        return cell;
    } else {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MapCell"];
        cell.textLabel.text = @"选择位置";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"开启后，系统将使用您设置的虚拟位置";
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1) {
        SimpleLocationMapViewController *mapVC = [[SimpleLocationMapViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:mapVC];
        
        mapVC.completionHandler = ^(CLLocationCoordinate2D coordinate) {
            g_fakeLocation = coordinate;
            saveLocationSettings();
            [self.tableView reloadData];
        };
        
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)toggleLocationSpoofing:(UISwitch *)sender {
    g_isLocationSpoofingEnabled = sender.isOn;
    saveLocationSettings();
    
    if (g_isLocationSpoofingEnabled) {
        NSLog(@"[DDGPS] 虚拟定位已启用: %.6f, %.6f", g_fakeLocation.latitude, g_fakeLocation.longitude);
    } else {
        NSLog(@"[DDGPS] 虚拟定位已禁用");
    }
}

@end

// MARK: - 导出函数
void setFakeLocation(double latitude, double longitude) {
    g_fakeLocation.latitude = latitude;
    g_fakeLocation.longitude = longitude;
    g_isLocationSpoofingEnabled = YES;
    saveLocationSettings();
    NSLog(@"[DDGPS] 虚拟位置已设置: %.6f, %.6f", latitude, longitude);
}

void disableLocationSpoofing() {
    g_isLocationSpoofingEnabled = NO;
    saveLocationSettings();
    NSLog(@"[DDGPS] 虚拟定位已禁用");
}

void enableLocationSpoofing() {
    g_isLocationSpoofingEnabled = YES;
    saveLocationSettings();
    NSLog(@"[DDGPS] 虚拟定位已启用");
}

// MARK: - 插件初始化
%ctor {
    @autoreleasepool {
        NSLog(@"[DDGPS] 插件初始化开始");
        
        // 加载设置
        loadLocationSettings();
        
        // 注册插件到微信插件管理器
        Class pluginsMgrClass = NSClassFromString(@"WCPluginsMgr");
        if (pluginsMgrClass && [pluginsMgrClass respondsToSelector:@selector(sharedInstance)]) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
             registerControllerWithTitle:PLUGIN_NAME 
             version:PLUGIN_VERSION 
             controller:@"SimpleSettingsViewController"];
            NSLog(@"[DDGPS] 插件已注册到微信");
        } else {
            NSLog(@"[DDGPS] 无法找到微信插件管理器");
        }
        
        NSLog(@"[DDGPS] 插件初始化完成");
    }
}