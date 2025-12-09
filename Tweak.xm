#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <AudioToolbox/AudioToolbox.h>

// MARK: - CLLocationManager 类别声明
@interface CLLocationManager (DDAssistant)

- (void)sendFakeLocationUpdate;

@end

// MARK: - 插件的配置管理类
@interface DDAssistantConfig : NSObject
+ (instancetype)sharedConfig;

@property (assign, nonatomic) BOOL fakeLocationEnabled;
@property (assign, nonatomic) double fakeLatitude;
@property (assign, nonatomic) double fakeLongitude;

@property (assign, nonatomic) BOOL customStepsEnabled;
@property (assign, nonatomic) NSInteger customStepsCount;
@property (strong, nonatomic) NSDate *lastStepsUpdateDate;
@end

@implementation DDAssistantConfig

static DDAssistantConfig *sharedInstance = nil;
static NSString *const kFakeLocationEnabledKey = @"DDAssistantFakeLocationEnabled";
static NSString *const kFakeLatitudeKey = @"DDAssistantFakeLatitude";
static NSString *const kFakeLongitudeKey = @"DDAssistantFakeLongitude";
static NSString *const kCustomStepsEnabledKey = @"DDAssistantCustomStepsEnabled";
static NSString *const kCustomStepsCountKey = @"DDAssistantCustomStepsCount";
static NSString *const kLastStepsUpdateDateKey = @"DDAssistantLastStepsUpdateDate";

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
        
        // 步数配置
        _customStepsEnabled = [defaults boolForKey:kCustomStepsEnabledKey];
        _customStepsCount = [defaults integerForKey:kCustomStepsCountKey];
        if (_customStepsCount == 0) {
            _customStepsCount = 8888;
            [defaults setInteger:_customStepsCount forKey:kCustomStepsCountKey];
        }
        
        NSDate *savedDate = [defaults objectForKey:kLastStepsUpdateDateKey];
        _lastStepsUpdateDate = savedDate ?: [NSDate date];
        if (!savedDate) {
            [defaults setObject:_lastStepsUpdateDate forKey:kLastStepsUpdateDateKey];
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

- (void)setCustomStepsEnabled:(BOOL)customStepsEnabled {
    _customStepsEnabled = customStepsEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:customStepsEnabled forKey:kCustomStepsEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setCustomStepsCount:(NSInteger)customStepsCount {
    _customStepsCount = customStepsCount;
    [[NSUserDefaults standardUserDefaults] setInteger:customStepsCount forKey:kCustomStepsCountKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setLastStepsUpdateDate:(NSDate *)lastStepsUpdateDate {
    _lastStepsUpdateDate = lastStepsUpdateDate;
    [[NSUserDefaults standardUserDefaults] setObject:lastStepsUpdateDate forKey:kLastStepsUpdateDateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Helper Methods
- (BOOL)isToday:(NSDate *)date {
    if (!date) return NO;
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *dateComponents = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    NSDateComponents *todayComponents = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    
    return (dateComponents.year == todayComponents.year &&
            dateComponents.month == todayComponents.month &&
            dateComponents.day == todayComponents.day);
}

@end

// MARK: - CLLocationManager 钩子扩展 (从 Tweak.x 中移植)

%hook CLLocationManager

// 伪造位置的方法实现
- (void)sendFakeLocationUpdate {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        // 创建一个准确的CLLocation对象
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(config.fakeLatitude, config.fakeLongitude);
        
        if (CLLocationCoordinate2DIsValid(coordinate)) {
            double accuracy = 5.0; // 默认精度
            double altitude = 0.0;
            double speed = 0.0;
            double course = 0.0;
            
            NSDate *timestamp = [NSDate date];
            
            // 创建完整的CLLocation对象，确保所有属性都有值
            CLLocation *fakeLocation = [[CLLocation alloc] 
                initWithCoordinate:coordinate
                altitude:altitude
                horizontalAccuracy:accuracy
                verticalAccuracy:accuracy
                course:course
                speed:speed
                timestamp:timestamp];
            
            // 确保代理方法存在后再调用
            if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
                });
            }
            
            // 确保回调块也被调用 - 使用更兼容的方式
            if (@available(iOS 14.0, *)) {
                SEL handlerSelector = NSSelectorFromString(@"locationUpdateHandler");
                if ([self respondsToSelector:handlerSelector]) {
                    id handler = [self valueForKey:@"locationUpdateHandler"];
                    if (handler && [handler isKindOfClass:NSClassFromString(@"NSBlock")]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // 使用performSelector调用block
                            typedef void (^LocationUpdateHandlerBlock)(CLLocationManager *, NSArray *, NSError *);
                            LocationUpdateHandlerBlock block = handler;
                            block(self, @[fakeLocation], nil);
                        });
                    }
                }
            }
        }
    }
}

- (void)startUpdatingLocation {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        // 拦截标准方法，启动自己的模拟器
        NSLog(@"[DD助手] 拦截并替换位置更新 - 使用模拟位置");
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendFakeLocationUpdate) object:nil];
        [self performSelector:@selector(sendFakeLocationUpdate) withObject:nil afterDelay:0.1];
        
        // 设置定时器持续发送虚拟位置
        static dispatch_source_t timer;
        if (timer) {
            dispatch_source_cancel(timer);
            timer = nil;
        }
        
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, 
                                 dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), 
                                 0.5 * NSEC_PER_SEC,  // 每0.5秒更新一次
                                 0.1 * NSEC_PER_SEC);
        
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(timer, ^{
            [weakSelf sendFakeLocationUpdate];
        });
        
        dispatch_resume(timer);
        
        // 保存定时器引用
        objc_setAssociatedObject(self, "fakeLocationTimer", timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        // 如果没有启用模拟，使用原始方法
        %orig;
    }
}

- (void)stopUpdatingLocation {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (!config.fakeLocationEnabled) {
        %orig;
    } else {
        // 停止定时器
        dispatch_source_t timer = objc_getAssociatedObject(self, "fakeLocationTimer");
        if (timer) {
            dispatch_source_cancel(timer);
            objc_setAssociatedObject(self, "fakeLocationTimer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

// 模拟方向数据
- (void)startUpdatingHeading {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (!config.fakeLocationEnabled) {
        %orig;
    } else {
        if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateHeading:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 添加轻微随机偏差，增加真实感
                double heading = 0.0;
                double headingJitter = ((double)arc4random() / UINT32_MAX - 0.5) * 2.0;
                heading += headingJitter;
                
                // 确保在0-360度范围内
                heading = fmod(heading + 360.0, 360.0);
                
                // 创建虚假的CLHeading对象
                CLHeading *fakeHeading = [[CLHeading alloc] init];
                
                // 使用KVC设置私有属性
                [fakeHeading setValue:@(heading) forKey:@"magneticHeading"];
                [fakeHeading setValue:@(heading) forKey:@"trueHeading"];
                [fakeHeading setValue:@(3.0 + ((double)arc4random() / UINT32_MAX) * 2.0) forKey:@"headingAccuracy"];
                [fakeHeading setValue:[NSDate date] forKey:@"timestamp"];
                
                [self.delegate locationManager:self didUpdateHeading:fakeHeading];
            });
        }
    }
}

// 模拟授权状态
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

- (CLAuthorizationStatus)_authorizationStatus {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// MARK: - CLLocation 钩子扩展 (从 Tweak.x 中移植)

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        double latitude = config.fakeLatitude;
        double longitude = config.fakeLongitude;
        
        return CLLocationCoordinate2DMake(latitude, longitude);
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        double baseAccuracy = 5.0;
        double jitter = ((double)arc4random() / UINT32_MAX) * 2.0;
        return baseAccuracy + jitter;
    }
    return %orig;
}

- (CLLocationDistance)altitude {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        double altitude = 0.0;
        // 添加微小随机变化
        double jitter = ((double)arc4random() / UINT32_MAX - 0.5) * 0.5;
        return altitude + jitter;
    }
    return %orig;
}

- (CLLocationAccuracy)verticalAccuracy {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        return 3.0 + ((double)arc4random() / UINT32_MAX) * 1.5;
    }
    return %orig;
}

- (CLLocationSpeed)speed {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        double speed = 0.0;
        // 添加轻微抖动
        double jitter = ((double)arc4random() / UINT32_MAX - 0.5) * 0.2 * speed;
        return fmax(0, speed + jitter); // 保证速度不为负
    }
    return %orig;
}

- (CLLocationDirection)course {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    if (config.fakeLocationEnabled) {
        double course = 0.0;
        return course;
    }
    return %orig;
}

%end

// MARK: - 插件的设置界面
@interface DDAssistantSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, MKMapViewDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray *sectionTitles;
@property (strong, nonatomic) NSArray *locationSectionRows;
@property (strong, nonatomic) NSArray *stepsSectionRows;

// 位置相关
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) CLGeocoder *geocoder;
@end

@implementation DDAssistantSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"DD助手设置";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    // 设置导航栏
    [self setupNavigationBar];
    
    // 初始化数据
    self.sectionTitles = @[@"位置设置", @"步数设置"];
    
    // 初始化表格行数据
    [self updateTableData];
    
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

- (void)updateTableData {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    // 位置设置部分
    NSMutableArray *locationRows = [NSMutableArray arrayWithObject:@"虚拟位置开关"];
    if (config.fakeLocationEnabled) {
        [locationRows addObject:@"地图选择位置"];
    }
    self.locationSectionRows = [locationRows copy];
    
    // 步数设置部分
    NSMutableArray *stepsRows = [NSMutableArray arrayWithObject:@"自定义步数开关"];
    if (config.customStepsEnabled) {
        [stepsRows addObject:@"设置步数"];
    }
    self.stepsSectionRows = [stepsRows copy];
}

- (void)backButtonTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableView DataSource & Delegate
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sectionTitles.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.locationSectionRows.count;
    } else {
        return self.stepsSectionRows.count;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sectionTitles[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellIdentifier = @"DDSettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }
    
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    NSString *title = nil;
    if (indexPath.section == 0) {
        title = self.locationSectionRows[indexPath.row];
    } else {
        title = self.stepsSectionRows[indexPath.row];
    }
    
    // 使用现代内容配置
    UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
    content.text = title;
    content.textProperties.color = [UIColor labelColor];
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = content;
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    
    if ([title isEqualToString:@"虚拟位置开关"]) {
        // 虚拟位置开关
        UISwitch *switchControl = [[UISwitch alloc] init];
        switchControl.onTintColor = [UIColor systemBlueColor];
        switchControl.on = config.fakeLocationEnabled;
        [switchControl addTarget:self action:@selector(fakeLocationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchControl;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        // 显示当前位置信息
        UIListContentConfiguration *updatedContent = [UIListContentConfiguration valueCellConfiguration];
        updatedContent.text = @"虚拟位置";
        updatedContent.secondaryText = config.fakeLocationEnabled ? 
            [NSString stringWithFormat:@"%.4f, %.4f", config.fakeLatitude, config.fakeLongitude] : 
            @"已关闭";
        updatedContent.textProperties.color = [UIColor labelColor];
        updatedContent.secondaryTextProperties.color = config.fakeLocationEnabled ? 
            [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
        cell.contentConfiguration = updatedContent;
        
    } else if ([title isEqualToString:@"自定义步数开关"]) {
        // 自定义步数开关
        UISwitch *switchControl = [[UISwitch alloc] init];
        switchControl.onTintColor = [UIColor systemBlueColor];
        switchControl.on = config.customStepsEnabled;
        [switchControl addTarget:self action:@selector(customStepsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchControl;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        // 显示当前步数信息
        UIListContentConfiguration *updatedContent = [UIListContentConfiguration valueCellConfiguration];
        updatedContent.text = @"自定义步数";
        updatedContent.secondaryText = config.customStepsEnabled ? 
            [NSString stringWithFormat:@"%ld步", (long)config.customStepsCount] : 
            @"已关闭";
        updatedContent.textProperties.color = [UIColor labelColor];
        updatedContent.secondaryTextProperties.color = config.customStepsEnabled ? 
            [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
        cell.contentConfiguration = updatedContent;
        
    } else if ([title isEqualToString:@"地图选择位置"]) {
        // 地图选择位置
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIListContentConfiguration *mapContent = [UIListContentConfiguration subtitleCellConfiguration];
        mapContent.text = @"地图选择位置";
        mapContent.secondaryText = @"点击选择或搜索位置";
        mapContent.textProperties.color = [UIColor labelColor];
        mapContent.secondaryTextProperties.color = [UIColor secondaryLabelColor];
        cell.contentConfiguration = mapContent;
        
    } else if ([title isEqualToString:@"设置步数"]) {
        // 设置步数
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIListContentConfiguration *stepsContent = [UIListContentConfiguration subtitleCellConfiguration];
        stepsContent.text = @"设置步数";
        stepsContent.secondaryText = [NSString stringWithFormat:@"当前：%ld步", (long)config.customStepsCount];
        stepsContent.textProperties.color = [UIColor labelColor];
        stepsContent.secondaryTextProperties.color = [UIColor secondaryLabelColor];
        cell.contentConfiguration = stepsContent;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *title = nil;
    if (indexPath.section == 0) {
        title = self.locationSectionRows[indexPath.row];
    } else {
        title = self.stepsSectionRows[indexPath.row];
    }
    
    if ([title isEqualToString:@"地图选择位置"]) {
        [self showMapSelectionView];
    } else if ([title isEqualToString:@"设置步数"]) {
        [self showStepsSettingAlert];
    }
}

#pragma mark - Switch Handlers
- (void)fakeLocationSwitchChanged:(UISwitch *)sender {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    config.fakeLocationEnabled = sender.on;
    
    // 更新表格数据并重新加载
    [self updateTableData];
    
    // 使用动画更新表格
    [self.tableView beginUpdates];
    
    // 如果开关被打开，插入地图选择位置行
    if (sender.on) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    } 
    // 如果开关被关闭，移除地图选择位置行
    else {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:0];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    }
    
    // 更新开关所在行
    NSIndexPath *switchIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[switchIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    
    [self.tableView endUpdates];
}

- (void)customStepsSwitchChanged:(UISwitch *)sender {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    config.customStepsEnabled = sender.on;
    
    // 更新表格数据并重新加载
    [self updateTableData];
    
    // 使用动画更新表格
    [self.tableView beginUpdates];
    
    // 如果开关被打开，插入设置步数行
    if (sender.on) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:1];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    } 
    // 如果开关被关闭，移除设置步数行
    else {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:1];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    }
    
    // 更新开关所在行
    NSIndexPath *switchIndexPath = [NSIndexPath indexPathForRow:0 inSection:1];
    [self.tableView reloadRowsAtIndexPaths:@[switchIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    
    [self.tableView endUpdates];
}

#pragma mark - Steps Setting
- (void)showStepsSettingAlert {
    DDAssistantConfig *config = [DDAssistantConfig sharedConfig];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置步数" 
                                                                   message:@"请输入自定义步数（0-100000）" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"步数";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.text = [NSString stringWithFormat:@"%ld", (long)config.customStepsCount];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确定" 
                                                            style:UIAlertActionStyleDefault 
                                                          handler:^(UIAlertAction *action) {
        UITextField *stepsField = alert.textFields[0];
        NSInteger steps = [stepsField.text integerValue];
        
        if (steps >= 0 && steps <= 100000) {
            config.customStepsCount = steps;
            config.lastStepsUpdateDate = [NSDate date];
            
            // 更新表格
            [self updateTableData];
            [self.tableView reloadData];
        } else {
            [self showAlertWithTitle:@"错误" message:@"请输入0-100000之间的步数"];
        }
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:confirmAction];
    
    [self presentViewController:alert animated:YES completion:nil];
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
    
    // 将X图标改为"取消"文字按钮
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(closeMapSelection)];
    mapVC.navigationItem.leftBarButtonItem = cancelButton;
    
    // 添加确认按钮
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
    navController.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = NO;
    
    [self presentViewController:navController animated:YES completion:nil];
    
    // 创建地图视图
    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.pointOfInterestFilter = [MKPointOfInterestFilter filterIncludingAllCategories];
    
    // 添加圆角效果
    self.mapView.layer.cornerRadius = 12;
    self.mapView.layer.masksToBounds = YES;
    self.mapView.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.mapView.layer.shadowOffset = CGSizeMake(0, 2);
    self.mapView.layer.shadowRadius = 8;
    self.mapView.layer.shadowOpacity = 0.15;
    
    [mapVC.view addSubview:self.mapView];
    
    // 创建搜索容器
    UIView *searchContainer = [[UIView alloc] init];
    searchContainer.backgroundColor = [UIColor clearColor];
    
    // 添加模糊效果
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.layer.cornerRadius = 12;
    blurView.layer.masksToBounds = YES;
    
    // 创建搜索栏
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地点或输入坐标";
    self.searchBar.searchBarStyle = UISearchBarStyleDefault;
    self.searchBar.barTintColor = [UIColor clearColor];
    self.searchBar.backgroundImage = [[UIImage alloc] init]; // 移除背景
    
    // 设置搜索文本框样式
    UITextField *searchTextField = self.searchBar.searchTextField;
    searchTextField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    searchTextField.layer.cornerRadius = 10;
    searchTextField.layer.masksToBounds = YES;
    searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    
    [blurView.contentView addSubview:self.searchBar];
    [searchContainer addSubview:blurView];
    [mapVC.view addSubview:searchContainer];
    
    // 添加提示标签
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"长按地图选择位置";
    hintLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.textColor = [UIColor secondaryLabelColor];
    hintLabel.backgroundColor = [UIColor clearColor];
    [mapVC.view addSubview:hintLabel];
    
    // 使用AutoLayout
    searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 搜索容器
        [searchContainer.topAnchor constraintEqualToAnchor:mapVC.view.safeAreaLayoutGuide.topAnchor constant:12],
        [searchContainer.leadingAnchor constraintEqualToAnchor:mapVC.view.leadingAnchor constant:16],
        [searchContainer.trailingAnchor constraintEqualToAnchor:mapVC.view.trailingAnchor constant:-16],
        [searchContainer.heightAnchor constraintEqualToConstant:52],
        
        // 模糊视图
        [blurView.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor],
        [blurView.topAnchor constraintEqualToAnchor:searchContainer.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:searchContainer.bottomAnchor],
        
        // 搜索栏
        [self.searchBar.leadingAnchor constraintEqualToAnchor:blurView.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:blurView.trailingAnchor],
        [self.searchBar.topAnchor constraintEqualToAnchor:blurView.topAnchor],
        [self.searchBar.bottomAnchor constraintEqualToAnchor:blurView.bottomAnchor],
        
        // 地图
        [self.mapView.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:16],
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
        // 震动反馈
        UIImpactFeedback