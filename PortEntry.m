//
//  PortEntry.m
//  AntManorPort
//
//  TrollFools 注入入口：只处理蚂蚁庄园（含家庭亲密度面板）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AntManorManager.h"
#import "AntManorIntimacy.h"
#import "AntManorCapture.h"

static const NSInteger AntManorButtonTag = 0x414E544D;
static NSString *const AntManorButtonXKey = @"manor_button_x";
static NSString *const AntManorButtonYKey = @"manor_button_y";

static NSURL *ManorURLFromController(UIViewController *controller) {
    if (!controller) return nil;
    @try {
        if ([controller respondsToSelector:@selector(url)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(url));
            if ([value isKindOfClass:NSURL.class]) return value;
            if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) return [NSURL URLWithString:value];
        }
        if ([controller respondsToSelector:@selector(currentURL)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(currentURL));
            if ([value isKindOfClass:NSURL.class]) return value;
            if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) return [NSURL URLWithString:value];
        }
        if ([controller respondsToSelector:@selector(webView)]) {
            id webView = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(webView));
            if ([webView respondsToSelector:@selector(URL)]) {
                return ((NSURL *(*)(id, SEL))objc_msgSend)(webView, @selector(URL));
            }
        }
    } @catch (NSException *exception) {}
    return nil;
}

static NSString *ManorText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return [(NSURL *)value absoluteString];
    return @"";
}

static UIViewController *ManorControllerFromBridge(id bridge) {
    if (![bridge respondsToSelector:@selector(contentView)]) return nil;
    id contentView = ((id (*)(id, SEL))objc_msgSend)(bridge, @selector(contentView));
    UIResponder *responder = [contentView isKindOfClass:UIResponder.class] ? contentView : nil;
    while (responder && ![responder isKindOfClass:UIViewController.class]) {
        responder = responder.nextResponder;
    }
    return [responder isKindOfClass:UIViewController.class] ? (UIViewController *)responder : nil;
}

#pragma mark - 面板

@interface AntManorPanel : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSString *> *summaryLines;
@end

@interface AntManorPanel ()
- (void)captureToggled:(UISwitch *)sender;
- (void)startTimedCaptureAction;
- (void)exportCaptureAction;
- (void)copyCapturePathAction;
- (void)showMessage:(NSString *)title message:(NSString *)message;
@end

@implementation AntManorPanel

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"蚂蚁庄园 · 家庭亲密度";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.summaryLines = [AntManorManager sharedInstance].intimacy.summaryLines;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(closePanel)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)closePanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reloadPanel {
    self.summaryLines = [AntManorManager sharedInstance].intimacy.summaryLines;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.summaryLines.count ?: 1;
    if (section == 1) return 2;
    if (section == 2) return 3;
    if (section == 3) return 4;
    NSArray *logs = [AntManorManager sharedInstance].logRecord;
    return logs.count ?: 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"今日状态";
        case 1: return @"自动化开关";
        case 2: return @"操作";
        case 3: return @"调试抓包（仅本地）";
        default: return @"运行日志";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AntManorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;

    AntManorManager *manager = [AntManorManager sharedInstance];

    if (indexPath.section == 0) {
        cell.textLabel.text = self.summaryLines.count ? self.summaryLines[indexPath.row] : @"暂无数据";
        cell.textLabel.textColor = indexPath.row >= 3 ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    } else if (indexPath.section == 1) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.onTintColor = [UIColor colorWithRed:0.07 green:0.36 blue:0.20 alpha:1.0];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"蚂蚁庄园自动任务";
            toggle.on = manager.enableAutoManor;
            [toggle addTarget:self action:@selector(autoManorChanged:) forControlEvents:UIControlEventValueChanged];
        } else {
            cell.textLabel.text = @"家庭亲密度自动化";
            toggle.on = manager.intimacy.activityEnabled;
            [toggle addTarget:self action:@selector(familyIntimacyChanged:) forControlEvents:UIControlEventValueChanged];
        }
        cell.accessoryView = toggle;
    } else if (indexPath.section == 2) {
        cell.textLabel.textColor = [UIColor colorWithRed:0.07 green:0.36 blue:0.20 alpha:1.0];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (indexPath.row == 0) cell.textLabel.text = @"查询当前亲密度排名";
        else if (indexPath.row == 1) cell.textLabel.text = @"重新加载亲密度配置";
        else cell.textLabel.text = @"清空日志";
    } else if (indexPath.section == 3) {
        AntManorCapture *capture = [AntManorCapture sharedInstance];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"调试抓包（NDJSON）";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.onTintColor = [UIColor colorWithRed:0.07 green:0.36 blue:0.20 alpha:1.0];
            toggle.on = capture.enabled;
            [toggle addTarget:self action:@selector(captureToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %ld 条 · %.2f MB",
                                         capture.enabled ? @"开" : @"关",
                                         (long)capture.recordCount,
                                         capture.currentFileSize / 1048576.0];
        } else {
            cell.textLabel.textColor = [UIColor colorWithRed:0.07 green:0.36 blue:0.20 alpha:1.0];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            if (indexPath.row == 1) cell.textLabel.text = @"开始抓包 60 秒";
            else if (indexPath.row == 2) cell.textLabel.text = @"导出抓包文件";
            else cell.textLabel.text = @"复制抓包路径";
        }
    } else {
        NSArray *logs = manager.logRecord;
        cell.textLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        if (indexPath.row < (NSInteger)logs.count) {
            cell.textLabel.text = logs[logs.count - indexPath.row - 1];
        } else {
            cell.textLabel.text = @"暂无日志";
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        if (indexPath.row == 1) [self startTimedCaptureAction];
        else if (indexPath.row == 2) [self exportCaptureAction];
        else if (indexPath.row == 3) [self copyCapturePathAction];
        return;
    }
    if (indexPath.section != 2) return;

    AntManorManager *manager = [AntManorManager sharedInstance];
    if (indexPath.row == 0) {
        [manager.intimacy queryRank];
        [manager addLog:[NSString stringWithFormat:@"排名查询：%@", manager.intimacy.statusNote]];
    } else if (indexPath.row == 1) {
        [manager.intimacy reloadConfig];
        [manager addLog:[NSString stringWithFormat:@"已重新加载亲密度配置：%@", manager.intimacy.configPath]];
    } else {
        @synchronized (manager.logRecord) {
            [manager.logRecord removeAllObjects];
        }
    }
    [self reloadPanel];
}

- (void)autoManorChanged:(UISwitch *)sender {
    AntManorManager *manager = [AntManorManager sharedInstance];
    manager.enableAutoManor = sender.on;
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"manor_enable_auto"];
    [manager addLog:[NSString stringWithFormat:@"蚂蚁庄园自动任务：%@", sender.on ? @"开启" : @"关闭"]];
    if (sender.on) [manager checkAndRunManorAutomations];
}

- (void)familyIntimacyChanged:(UISwitch *)sender {
    AntManorManager *manager = [AntManorManager sharedInstance];
    manager.enableFamilyIntimacy = sender.on;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:sender.on forKey:@"manor_enable_family_intimacy"];
    [defaults setBool:sender.on forKey:@"manor_cfg_activityEnabled"];
    [manager.intimacy reloadConfig];
    [manager addLog:[NSString stringWithFormat:@"家庭亲密度自动化：%@", sender.on ? @"开启" : @"关闭"]];
    [self reloadPanel];
}

- (void)captureToggled:(UISwitch *)sender {
    [AntManorCapture sharedInstance].enabled = sender.on;
    [self reloadPanel];
}

- (void)startTimedCaptureAction {
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开始抓包 60 秒"
                                                                   message:@"请现在去蚂蚁庄园「家庭」页面操作任务。60 秒后自动停止，随后点击「导出抓包文件」，把导出的文件发给开发者分析。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        AntManorPanel *panel = weakSelf;
        if (!panel) return;
        [[AntManorCapture sharedInstance] startTimedCapture:60 completion:^{
            [panel reloadPanel];
        }];
        [panel reloadPanel];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportCaptureAction {
    NSArray<NSURL *> *urls = [[AntManorCapture sharedInstance] exportFileURLs];
    if (!urls.count) {
        [self showMessage:@"暂无抓包文件"
                    message:@"请先开启抓包并操作蚂蚁庄园「家庭」页面，或点击「开始抓包 60 秒」后再导出。"];
        return;
    }
    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:controller animated:YES completion:^{
        [self.tableView reloadData];
    }];
}

- (void)copyCapturePathAction {
    NSString *path = [[AntManorCapture sharedInstance] exportPathDescription];
    UIPasteboard.generalPasteboard.string = path ?: @"";
    [self showMessage:@"抓包路径已复制"
                message:[NSString stringWithFormat:@"%@\n\n可用 Filza 或文件 App 进入该目录；导出时直接分享 ndjson 文件即可。", path ?: @""]];
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - 悬浮按钮

static void ManorShowPanel(UIButton *button) {
    UIResponder *responder = button;
    while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
    UIViewController *presenter = (UIViewController *)responder;
    if (!presenter) presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter) return;

    AntManorPanel *panel = [[AntManorPanel alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:panel];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [presenter presentViewController:nav animated:YES completion:nil];
}

static void ManorHandlePan(UIPanGestureRecognizer *gesture) {
    UIButton *button = (UIButton *)gesture.view;
    UIView *parent = button.superview;
    if (!parent) return;
    CGPoint translation = [gesture translationInView:parent];
    CGPoint center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    UIEdgeInsets safe = parent.safeAreaInsets;
    center.x = MIN(MAX(center.x, safe.left + 30), parent.bounds.size.width - safe.right - 30);
    center.y = MIN(MAX(center.y, safe.top + 30), parent.bounds.size.height - safe.bottom - 30);
    button.center = center;
    [gesture setTranslation:CGPointZero inView:parent];

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (parent.bounds.size.width > 0 && parent.bounds.size.height > 0) {
            [defaults setFloat:button.center.x / parent.bounds.size.width forKey:AntManorButtonXKey];
            [defaults setFloat:button.center.y / parent.bounds.size.height forKey:AntManorButtonYKey];
        }
    }
}

static void ManorButtonPan(id self, SEL _cmd, UIPanGestureRecognizer *gesture) {
    ManorHandlePan(gesture);
}

static UIButton *ManorEnsureButton(UIViewController *controller) {
    UIWindow *window = controller.view.window ?: UIApplication.sharedApplication.keyWindow;
    UIView *parent = window ?: controller.view;
    if (!parent) return nil;

    UIButton *existing = (UIButton *)[parent viewWithTag:AntManorButtonTag];
    if (existing) return existing;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = AntManorButtonTag;
    button.backgroundColor = [UIColor colorWithRed:0.06 green:0.28 blue:0.16 alpha:0.95];
    button.tintColor = UIColor.whiteColor;
    button.layer.cornerRadius = 24;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.25;
    button.layer.shadowRadius = 6;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    button.frame = CGRectMake(parent.bounds.size.width - 64, parent.safeAreaInsets.top + 160, 48, 48);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [button setImage:[UIImage systemImageNamed:@"leaf.fill"] forState:UIControlStateNormal];
    __weak UIButton *weakButton = button;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        UIButton *strongButton = weakButton;
        if (strongButton) ManorShowPanel(strongButton);
    }] forControlEvents:UIControlEventTouchUpInside];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat savedX = [defaults floatForKey:AntManorButtonXKey];
    CGFloat savedY = [defaults floatForKey:AntManorButtonYKey];
    if (savedX > 0 && savedY > 0) {
        button.center = CGPointMake(savedX * parent.bounds.size.width, savedY * parent.bounds.size.height);
    }

    Class parentClass = [parent class];
    if (!class_getInstanceMethod(parentClass, @selector(manorHandlePan:))) {
        class_addMethod(parentClass, @selector(manorHandlePan:), (IMP)ManorButtonPan, "v@:@");
    }
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:parent action:@selector(manorHandlePan:)];
    [button addGestureRecognizer:pan];

    [parent addSubview:button];
    return button;
}

#pragma mark - Hook

static IMP originalViewDidAppear = NULL;
static IMP originalTransformResponseData = NULL;
static IMP originalDoFlushMessageQueue = NULL;
static IMP originalDispatchMessage = NULL;

static void PortViewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (originalViewDidAppear) ((void (*)(id, SEL, BOOL))originalViewDidAppear)(self, _cmd, animated);

    NSURL *url = ManorURLFromController(self);
    AntManorManager *manager = [AntManorManager sharedInstance];
    UIButton *button = ManorEnsureButton(self);

    if ([AntManorManager isManorURL:url]) {
        button.hidden = NO;
        if (url.absoluteString.length) manager.manorH5Url = url.absoluteString;
        [manager checkAndRunManorAutomations];
        [manager recordStage:[NSString stringWithFormat:@"进入蚂蚁庄园页面：%@", url.absoluteString.length ? url.absoluteString : @"(unknown)"]];
    } else {
        button.hidden = YES;
    }
}

static id PortTransformResponseData(id self, SEL _cmd, id value) {
    AntManorManager *manager = [AntManorManager sharedInstance];
    NSDictionary *dict = [value isKindOfClass:NSDictionary.class] ? value : nil;
    NSString *bridgeUrl = [manager effectiveUrlForBridge:self];

    [[AntManorCapture sharedInstance] recordResponse:value url:bridgeUrl];

    BOOL isManor = dict ? [AntManorManager isManorResponse:dict] : NO;
    if (!isManor && bridgeUrl.length && [AntManorManager isManorURL:[NSURL URLWithString:bridgeUrl]]) isManor = YES;

    if (isManor) {
        if ((id)manager.manorBridge != self) {
            [manager registerManorBridge:self url:bridgeUrl];
            [manager recordStage:@"已绑定蚂蚁庄园 H5 Bridge"];
        }
        UIViewController *manorController = ManorControllerFromBridge(self);
        if (manorController) {
            UIButton *button = ManorEnsureButton(manorController);
            button.hidden = NO;
        }
        [manager handleManorResponse:dict ?: @{}];

        NSString *responseId = ManorText(dict[@"responseId"] ?: dict[@"callbackId"]);
        if ([responseId containsString:@"rpc_manor_"]) {
            NSMutableDictionary *safe = [NSMutableDictionary dictionary];
            safe[@"resultStatus"] = @1000;
            safe[@"resultCode"] = @"SUCCESS";
            safe[@"success"] = @YES;
            safe[@"resData"] = @{@"success": @YES, @"resultCode": @"SUCCESS"};
            safe[@"responseId"] = responseId;
            if (originalTransformResponseData) {
                return ((id (*)(id, SEL, id))originalTransformResponseData)(self, _cmd, safe);
            }
            return safe;
        }
    }

    if (originalTransformResponseData) {
        return ((id (*)(id, SEL, id))originalTransformResponseData)(self, _cmd, value);
    }
    return value;
}

static void ManorUpdateLastOperationType(id message) {
    @try {
        NSString *messageString = nil;
        if ([message isKindOfClass:NSString.class]) {
            messageString = message;
        } else if ([NSJSONSerialization isValidJSONObject:message]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
            if (data.length) messageString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if (messageString.length) {
            static NSRegularExpression *regex = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                regex = [NSRegularExpression regularExpressionWithPattern:@"\"operationType\"\\s*:\\s*\"([^\"]+)\"" options:0 error:nil];
            });
            NSTextCheckingResult *match = [regex firstMatchInString:messageString options:0 range:NSMakeRange(0, messageString.length)];
            if (match.numberOfRanges > 1) {
                [AntManorManager sharedInstance].lastRpcOperationType = [messageString substringWithRange:[match rangeAtIndex:1]];
            }
        }
    } @catch (NSException *exception) {}
}

static void PortDoFlushMessageQueue(id self, SEL _cmd, id message, id url) {
    @try {
        [[AntManorCapture sharedInstance] recordRequestMessage:message url:url];
    } @catch (NSException *exception) {}
    ManorUpdateLastOperationType(message);
    if (originalDoFlushMessageQueue) {
        ((void (*)(id, SEL, id, id))originalDoFlushMessageQueue)(self, _cmd, message, url);
    }
}

// 家庭页的请求可能走 fast-mode 的 message dispatch（不经 _doFlushMessageQueue），
// 这里补一层，确保请求侧也能被抓到；同 callbackId 由抓包模块去重。
static void PortDispatchMessage(id self, SEL _cmd, id message) {
    @try {
        NSString *bridgeUrl = [[AntManorManager sharedInstance] effectiveUrlForBridge:self];
        [[AntManorCapture sharedInstance] recordRequestMessage:message url:bridgeUrl];
    } @catch (NSException *exception) {}
    ManorUpdateLastOperationType(message);
    if (originalDispatchMessage) {
        ((void (*)(id, SEL, id))originalDispatchMessage)(self, _cmd, message);
    }
}

static BOOL InstallMethodHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    IMP current = method_getImplementation(method);
    if (current == replacement) return NO;
    if (original && !*original) *original = current;
    method_setImplementation(method, replacement);
    return YES;
}

static BOOL ManorClassOwnsMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL owns = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            owns = YES;
            break;
        }
    }
    if (methods) free(methods);
    return owns;
}

// 只 hook 页面控制器自身（或其父类，但绝不 hook UIViewController 本身）实现的方法，避免影响全 App。
static BOOL InstallControllerHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    Class owner = cls;
    while (owner && owner != UIViewController.class) {
        if (ManorClassOwnsMethod(owner, selector)) {
            return InstallMethodHook(cls, selector, replacement, original);
        }
        owner = class_getSuperclass(owner);
    }
    return NO;
}

static void ManorInstallMarker(id self, SEL _cmd) {}

__attribute__((constructor))
static void InstallManorHooks(void) {
    @autoreleasepool {
        BOOL shouldInstall = NO;
        @synchronized (NSProcessInfo.class) {
            shouldInstall = class_addMethod(NSProcessInfo.class, sel_registerName("antmanorHooksInstalled"), (IMP)ManorInstallMarker, "v@:");
        }
        if (!shouldInstall) return;

        AntManorManager *manager = [AntManorManager sharedInstance];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        manager.enableAutoManor = [defaults objectForKey:@"manor_enable_auto"] ? [defaults boolForKey:@"manor_enable_auto"] : YES;
        manager.enableFamilyIntimacy = [defaults objectForKey:@"manor_enable_family_intimacy"] ? [defaults boolForKey:@"manor_enable_family_intimacy"] : NO;

        Class webController = NSClassFromString(@"H5WebViewController");
        if (webController) {
            InstallControllerHook(webController, @selector(viewDidAppear:), (IMP)PortViewDidAppear, &originalViewDidAppear);
        }

        Class bridgeClass = NSClassFromString(@"PSDJsBridge") ?: NSClassFromString(@"RVKJsBridge");
        if (bridgeClass) {
            InstallMethodHook(bridgeClass, @selector(transformResponseData:), (IMP)PortTransformResponseData, &originalTransformResponseData);
            InstallMethodHook(bridgeClass, @selector(_doFlushMessageQueue:url:), (IMP)PortDoFlushMessageQueue, &originalDoFlushMessageQueue);
            InstallMethodHook(bridgeClass, @selector(_dispatchMessage:), (IMP)PortDispatchMessage, &originalDispatchMessage);
        }

        [manager recordStage:@"蚂蚁庄园插件已注入（仅庄园 + 家庭亲密度）"];
        NSLog(@"[AntManorPort] hooks installed");
    }
}
