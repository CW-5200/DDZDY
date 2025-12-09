#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#define PLUGIN_NAME @"DD虚拟定位"
#define PLUGIN_VERSION @"1.0.0"

// MARK: - 设置键名
static NSString * const kFakeLocationEnabledKey = @"com.dd.virtual.location.enabled";
static NSString * const kFakeLatitudeKey = @"com.dd.virtual.location.latitude";
static NSString * const kFakeLongitudeKey = @"com.dd.virtual.location.longitude";

// MARK: - 全局变量
static BOOL gFakeLocationEnabled = NO;
static double gFakeLatitude = 39.9035;
static double gFakeLongitude = 116.3976;

// MARK: - 微信类声明
@interface MMLocationMgr : NSObject
- (void)locationManager:(id)arg1 didUpdateToLocation:(id)arg2 fromLocation:(id)arg3;
- (void)locationManager:(id)arg1 didUpdateLocations:(NSArray *)arg2;
- (id)getLastLocationCache;
- (id)getRealtimeLocationCache;
- (void)updateLocationCache:(id)arg1 isMarsLocation:(_Bool)arg2;
- (unsigned long long)updateAddressByLocation:(struct CLLocationCoordinate2D)arg1;
- (id)getAddressByLocation:(struct CLLocationCoordinate2D)arg1;
@end

@interface WCLocationInfo : NSObject
- (double)latitude;
- (double)longitude;
@end

@interface WCLocationGetter : NSObject
- (CLLocation *)location;
- (CLLocationCoordinate2D)coordinate;
@end

// MARK: - 设置状态检查函数
static BOOL isFakeLocationEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kFakeLocationEnabledKey];
}

static double getFakeLatitude() {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kFakeLatitudeKey];
}

static double getFakeLongitude() {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kFakeLongitudeKey];
}

static void loadLocationSettings() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    gFakeLocationEnabled = [defaults boolForKey:kFakeLocationEnabledKey];
    gFakeLatitude = [defaults doubleForKey:kFakeLatitudeKey];
    gFakeLongitude = [defaults doubleForKey:kFakeLongitudeKey];
    
    if (gFakeLatitude == 0 && gFakeLongitude == 0) {
        gFakeLatitude = 39.9035;
        gFakeLongitude = 116.3976;
        [defaults setDouble:gFakeLatitude forKey:kFakeLatitudeKey];
        [defaults setDouble:gFakeLongitude forKey:kFakeLongitudeKey];
        [defaults synchronize];
    }
}

// MARK: - 地图选择视图控制器
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
    
    CLLocationCoordinate2D initialCoord = CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude());
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
        [defaults setDouble:coordinate.latitude forKey:kFakeLatitudeKey];
        [defaults setDouble:coordinate.longitude forKey:kFakeLongitudeKey];
        [defaults synchronize];
        
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
        return [[NSUserDefaults standardUserDefaults] boolForKey:kFakeLocationEnabledKey] ? 1 : 0;
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
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
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
        switchView.on = [defaults boolForKey:kFakeLocationEnabledKey];
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
        
        double latitude = [defaults doubleForKey:kFakeLatitudeKey];
        double longitude = [defaults doubleForKey:kFakeLongitudeKey];
        
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
    [defaults setBool:sender.isOn forKey:kFakeLocationEnabledKey];
    [defaults synchronize];
    
    [self.tableView reloadData];
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        CFSTR("com.dd.virtual.location.settings_changed"),
                                        NULL,
                                        NULL,
                                        YES);
}

@end

// MARK: - Hook实现
%hook MMLocationMgr

- (void)locationManager:(id)arg1 didUpdateToLocation:(id)arg2 fromLocation:(id)arg3 {
    if (isFakeLocationEnabled()) {
        CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude())
                                                                 altitude:arg2 ? [arg2 altitude] : 0
                                                       horizontalAccuracy:arg2 ? [arg2 horizontalAccuracy] : 10
                                                         verticalAccuracy:arg2 ? [arg2 verticalAccuracy] : 10
                                                                timestamp:arg2 ? [arg2 timestamp] : [NSDate date]];
        %orig(arg1, fakeLocation, arg3);
    } else {
        %orig(arg1, arg2, arg3);
    }
}

- (void)locationManager:(id)arg1 didUpdateLocations:(NSArray *)arg2 {
    if (isFakeLocationEnabled()) {
        CLLocation *originalLocation = arg2.firstObject;
        CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude())
                                                                 altitude:originalLocation ? [originalLocation altitude] : 0
                                                       horizontalAccuracy:originalLocation ? [originalLocation horizontalAccuracy] : 10
                                                         verticalAccuracy:originalLocation ? [originalLocation verticalAccuracy] : 10
                                                                timestamp:originalLocation ? [originalLocation timestamp] : [NSDate date]];
        %orig(arg1, @[fakeLocation]);
    } else {
        %orig(arg1, arg2);
    }
}

- (id)getLastLocationCache {
    if (isFakeLocationEnabled()) {
        id fakeCache = %orig;
        if (fakeCache) {
            @try {
                [fakeCache setValue:@(getFakeLatitude()) forKey:@"latitude"];
                [fakeCache setValue:@(getFakeLongitude()) forKey:@"longitude"];
            } @catch (NSException *exception) {
                NSLog(@"DD虚拟定位: 设置位置缓存失败: %@", exception);
            }
        }
        return fakeCache;
    }
    return %orig;
}

- (id)getRealtimeLocationCache {
    if (isFakeLocationEnabled()) {
        id fakeCache = %orig;
        if (fakeCache) {
            @try {
                [fakeCache setValue:@(getFakeLatitude()) forKey:@"latitude"];
                [fakeCache setValue:@(getFakeLongitude()) forKey:@"longitude"];
            } @catch (NSException *exception) {
                NSLog(@"DD虚拟定位: 设置实时位置缓存失败: %@", exception);
            }
        }
        return fakeCache;
    }
    return %orig;
}

- (void)updateLocationCache:(id)arg1 isMarsLocation:(_Bool)arg2 {
    if (isFakeLocationEnabled()) {
        CLLocation *originalLocation = (CLLocation *)arg1;
        CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude())
                                                                 altitude:[originalLocation altitude]
                                                       horizontalAccuracy:[originalLocation horizontalAccuracy]
                                                         verticalAccuracy:[originalLocation verticalAccuracy]
                                                                timestamp:[originalLocation timestamp]];
        %orig(fakeLocation, arg2);
    } else {
        %orig(arg1, arg2);
    }
}

- (unsigned long long)updateAddressByLocation:(struct CLLocationCoordinate2D)arg1 {
    if (isFakeLocationEnabled()) {
        CLLocationCoordinate2D fakeCoord = CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude());
        return %orig(fakeCoord);
    }
    return %orig(arg1);
}

- (id)getAddressByLocation:(struct CLLocationCoordinate2D)arg1 {
    if (isFakeLocationEnabled()) {
        CLLocationCoordinate2D fakeCoord = CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude());
        return %orig(fakeCoord);
    }
    return %orig(arg1);
}

%end

%hook WCLocationInfo
- (double)latitude {
    if (isFakeLocationEnabled()) {
        return getFakeLatitude();
    }
    return %orig;
}

- (double)longitude {
    if (isFakeLocationEnabled()) {
        return getFakeLongitude();
    }
    return %orig;
}
%end

%hook WCLocationGetter
- (CLLocation *)location {
    if (isFakeLocationEnabled()) {
        CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:getFakeLatitude() 
                                                              longitude:getFakeLongitude()];
        return fakeLocation;
    }
    return %orig;
}

- (CLLocationCoordinate2D)coordinate {
    if (isFakeLocationEnabled()) {
        return CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude());
    }
    return %orig;
}
%end

%hook CLLocationManager
- (void)startUpdatingLocation {
    if (isFakeLocationEnabled()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:getFakeLatitude() 
                                                                  longitude:getFakeLongitude()];
            
            if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
            }
            
            if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
                [self.delegate locationManager:self didUpdateToLocation:fakeLocation fromLocation:nil];
            }
        });
    } else {
        %orig;
    }
}

- (CLLocation *)location {
    if (isFakeLocationEnabled()) {
        return [[CLLocation alloc] initWithLatitude:getFakeLatitude() 
                                          longitude:getFakeLongitude()];
    }
    return %orig;
}
%end

%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    if (isFakeLocationEnabled()) {
        static dispatch_once_t onceToken;
        static BOOL isInOurCode = NO;
        dispatch_once(&onceToken, ^{
            NSArray *callStackSymbols = [NSThread callStackSymbols];
            NSString *callStackString = [callStackSymbols componentsJoinedByString:@""];
            isInOurCode = [callStackString containsString:@"DD虚拟定位"] || 
                         [callStackString containsString:@"DDVirtualLocation"];
        });
        
        if (!isInOurCode) {
            return CLLocationCoordinate2DMake(getFakeLatitude(), getFakeLongitude());
        }
    }
    return %orig;
}

- (double)latitude {
    if (isFakeLocationEnabled()) {
        static dispatch_once_t onceToken;
        static BOOL isInOurCode = NO;
        dispatch_once(&onceToken, ^{
            NSArray *callStackSymbols = [NSThread callStackSymbols];
            NSString *callStackString = [callStackSymbols componentsJoinedByString:@""];
            isInOurCode = [callStackString containsString:@"DD虚拟定位"] || 
                         [callStackString containsString:@"DDVirtualLocation"];
        });
        
        if (!isInOurCode) {
            return getFakeLatitude();
        }
    }
    return %orig;
}

- (double)longitude {
    if (isFakeLocationEnabled()) {
        static dispatch_once_t onceToken;
        static BOOL isInOurCode = NO;
        dispatch_once(&onceToken, ^{
            NSArray *callStackSymbols = [NSThread callStackSymbols];
            NSString *callStackString = [callStackSymbols componentsJoinedByString:@""];
            isInOurCode = [callStackString containsString:@"DD虚拟定位"] || 
                         [callStackString containsString:@"DDVirtualLocation"];
        });
        
        if (!isInOurCode) {
            return getFakeLongitude();
        }
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
        
        if (![defaults objectForKey:kFakeLocationEnabledKey]) {
            [defaults setBool:NO forKey:kFakeLocationEnabledKey];
        }
        
        if ([defaults doubleForKey:kFakeLatitudeKey] == 0 && [defaults doubleForKey:kFakeLongitudeKey] == 0) {
            [defaults setDouble:39.9035 forKey:kFakeLatitudeKey];
            [defaults setDouble:116.3976 forKey:kFakeLongitudeKey];
        }
        
        [defaults synchronize];
        
        loadLocationSettings();
        
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        (CFNotificationCallback)loadLocationSettings,
                                        CFSTR("com.dd.virtual.location.settings_changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        
        Class pluginsMgrClass = NSClassFromString(@"WCPluginsMgr");
        if (pluginsMgrClass && [pluginsMgrClass respondsToSelector:@selector(sharedInstance)]) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] registerControllerWithTitle:PLUGIN_NAME 
                                                                               version:PLUGIN_VERSION 
                                                                           controller:@"DDVirtualLocationSettingsViewController"];
        }
    }
}