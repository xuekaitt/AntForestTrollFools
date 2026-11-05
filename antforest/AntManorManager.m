//
//  AntManorManager.m
//  AntManorPort
//

#import "AntManorManager.h"
#import "AntManorCapture.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString *const kManorFoodDoneDateKey = @"manor_food_done_date";
static NSString *const kManorFoodDoneListKey = @"manor_food_done_list";
static NSString *const kManorManureDoneListKey = @"manor_manure_done_list";

static NSString *ManorDateString(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd";
    });
    return [formatter stringFromDate:[NSDate date]];
}

static NSString *ManorRandomString(NSInteger length) {
    static NSString *const chars = @"0123456789abcdef";
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    for (NSInteger i = 0; i < length; i++) {
        [result appendFormat:@"%C", [chars characterAtIndex:arc4random_uniform((uint32_t)chars.length)]];
    }
    return result;
}

static NSString *ManorString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSInteger ManorInteger(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value integerValue];
    return 0;
}

static NSDictionary *ManorPayloadFromResponse(NSDictionary *dict) {
    for (NSString *key in @[@"resData", @"data", @"result"]) {
        id value = dict[key];
        if ([value isKindOfClass:NSDictionary.class]) return value;
    }
    return dict;
}

@interface AntManorManager ()
@property (nonatomic, strong) NSLock *flushLock;
@property (nonatomic, assign) NSTimeInterval lastAutomationCheckTime;
@property (nonatomic, assign) NSTimeInterval lastFeedTime;
@property (nonatomic, assign) NSTimeInterval lastTaskQueryTime;
@property (nonatomic, assign) NSTimeInterval lastRankQueryTime;
@property (nonatomic, assign) NSTimeInterval lastManureCollectTime;
@property (nonatomic, assign) NSTimeInterval lastAnswerAttemptTime;
@property (nonatomic, assign) NSTimeInterval lastFeedWarnTime;
@property (nonatomic, strong) NSMutableSet<NSString *> *foodDoneTasks;
@property (nonatomic, strong) NSMutableSet<NSString *> *manureDonePots;
@property (nonatomic, strong) NSString *foodDoneDate;
@property (nonatomic, strong) AntManorIntimacy *intimacy;
@end

@implementation AntManorManager

+ (instancetype)sharedInstance {
    static AntManorManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AntManorManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _flushLock = [[NSLock alloc] init];
        _logRecord = [NSMutableArray array];
        _manorH5Url = @"https://66666674.h5app.alipay.com/www/index.html";
        _lastManorFoodStockLimit = 1800;
        _intimacy = [AntManorIntimacy sharedInstance];
        __weak typeof(self) weakSelf = self;
        _intimacy.logHandler = ^(NSString *message) {
            [weakSelf addLog:message];
        };
        _intimacy.requestHandler = ^(NSString *operationType, NSArray *requestData, NSString *callbackPrefix) {
            [weakSelf sendManorRPC:operationType requestData:requestData callbackPrefix:callbackPrefix];
        };
        [AntManorCapture sharedInstance].logHandler = ^(NSString *message) {
            [weakSelf addLog:message];
        };
        [self loadFoodDoneState];
    }
    return self;
}

#pragma mark - 页面识别

+ (BOOL)isManorURL:(NSURL *)url {
    if (!url) return NO;
    NSString *text = url.absoluteString.lowercaseString;
    return [text containsString:@"66666674"] ||
           [text containsString:@"2017090512380701"] ||
           [text containsString:@"antfarm"] ||
           [text containsString:@"ant_farm"];
}

+ (BOOL)isManorResponse:(id)value {
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *dict = (NSDictionary *)value;
    NSDictionary *resData = ManorPayloadFromResponse(dict);

    if (dict[@"bubbles"] || resData[@"bubbles"] ||
        dict[@"wateringBubbles"] || resData[@"wateringBubbles"] ||
        dict[@"totalDatas"] || resData[@"totalDatas"] ||
        dict[@"friendRanking"] || resData[@"friendRanking"] ||
        dict[@"combineHandlerVOMap"] || resData[@"combineHandlerVOMap"] ||
        dict[@"limitedTimeChallenge"] || resData[@"limitedTimeChallenge"] ||
        dict[@"manureFactory"] || resData[@"manureFactory"] ||
        dict[@"subplotsActivityList"] || resData[@"subplotsActivityList"]) {
        return NO;
    }

    NSString *opType = ManorString(dict[@"operationType"] ?: resData[@"operationType"]);
    if ([opType containsString:@"antfarm"] || [opType containsString:@"ant_farm"]) return YES;
    if ([opType containsString:@"family"] || [opType containsString:@"intimacy"]) return YES;
    if (resData[@"subFarmVO"] || dict[@"subFarmVO"]) return YES;
    if (resData[@"dynamicGlobalConfig"] || dict[@"dynamicGlobalConfig"]) return YES;
    if (resData[@"farmTaskList"] || dict[@"farmTaskList"]) return YES;
    if (resData[@"signList"] || dict[@"signList"]) return YES;
    if (resData[@"familyInfo"] || dict[@"familyInfo"]) return YES;
    if (resData[@"familyActivity"] || dict[@"familyActivity"]) return YES;
    if (resData[@"familyTaskList"] || dict[@"familyTaskList"]) return YES;
    // 抓包实测：家庭页任务列表直接放在顶层 familyTasks，且带活动/亲密度字段
    if (resData[@"familyTasks"] || dict[@"familyTasks"]) return YES;
    if (resData[@"familyActivityIntimateNumber"] || dict[@"familyActivityIntimateNumber"]) return YES;
    if (resData[@"familyDailyIntimateNumber"] || dict[@"familyDailyIntimateNumber"]) return YES;
    if (resData[@"familyIntimateAwardGear"] || dict[@"familyIntimateAwardGear"]) return YES;
    if (resData[@"activityInfo"] || dict[@"activityInfo"]) return YES;
    if (resData[@"intimacyInfo"] || dict[@"intimacyInfo"]) return YES;
    return NO;
}

#pragma mark - 桥接

- (void)registerManorBridge:(id)bridge url:(NSString *)url {
    if (!bridge) return;
    self.manorBridge = (PSDJsBridge *)bridge;
    NSString *effectiveUrl = url.length ? url : [self effectiveUrlForBridge:bridge];
    if (effectiveUrl.length) self.manorH5Url = effectiveUrl;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(800 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [weakSelf checkAndRunManorAutomations];
    });
}

- (NSString *)effectiveUrlForBridge:(id)bridge {
    if (!bridge) return nil;
    @try {
        id cv = [bridge respondsToSelector:@selector(contentView)] ? ((id (*)(id, SEL))objc_msgSend)(bridge, @selector(contentView)) : nil;
        if ([cv respondsToSelector:@selector(url)]) {
            id u = ((id (*)(id, SEL))objc_msgSend)(cv, @selector(url));
            if ([u isKindOfClass:NSURL.class] && [(NSURL *)u absoluteString].length) return [(NSURL *)u absoluteString];
            if ([u isKindOfClass:NSString.class] && [(NSString *)u length]) return (NSString *)u;
        }
        if ([cv respondsToSelector:@selector(URL)]) {
            id u = ((id (*)(id, SEL))objc_msgSend)(cv, @selector(URL));
            if ([u isKindOfClass:NSURL.class] && [(NSURL *)u absoluteString].length) return [(NSURL *)u absoluteString];
        }
        if ([cv respondsToSelector:@selector(webView)]) {
            id wv = ((id (*)(id, SEL))objc_msgSend)(cv, @selector(webView));
            if ([wv respondsToSelector:@selector(URL)]) {
                id u = ((id (*)(id, SEL))objc_msgSend)(wv, @selector(URL));
                if ([u isKindOfClass:NSURL.class] && [(NSURL *)u absoluteString].length) return [(NSURL *)u absoluteString];
            }
        }
        if ([bridge respondsToSelector:@selector(webView)]) {
            id wv = ((id (*)(id, SEL))objc_msgSend)(bridge, @selector(webView));
            if ([wv respondsToSelector:@selector(URL)]) {
                id u = ((id (*)(id, SEL))objc_msgSend)(wv, @selector(URL));
                if ([u isKindOfClass:NSURL.class] && [(NSURL *)u absoluteString].length) return [(NSURL *)u absoluteString];
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

- (void)sendManorRPC:(NSString *)operationType requestData:(NSArray *)requestData callbackPrefix:(NSString *)callbackPrefix {
    if (!operationType.length) return;
    if (![requestData isKindOfClass:NSArray.class]) requestData = @[];

    __weak typeof(self) weakSelf = self;
    void (^sendBlock)(void) = ^{
        AntManorManager *strongSelf = weakSelf;
        if (!strongSelf) return;
        PSDJsBridge *bridge = strongSelf.manorBridge;
        if (!bridge) {
            [strongSelf addLog:@"RPC 发送失败：庄园桥接尚未就绪"];
            return;
        }
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *callbackId = [NSString stringWithFormat:@"rpc_%@%lld.%@", callbackPrefix ?: @"manor_", (long long)(now * 1000), ManorRandomString(15)];
        NSDictionary *headers = @{
            @"source": @"chInfo_ch_appcenter__chsub_9patch",
            @"ags-source": @"chInfo_ch_appcenter__chsub_9patch"
        };
        NSDictionary *data = @{
            @"operationType": operationType,
            @"headers": headers,
            @"showError": @NO,
            @"showLoading": @NO,
            @"getResponse": @YES,
            @"requestData": requestData
        };
        NSDictionary *message = @{
            @"handlerName": @"rpc",
            @"data": data,
            @"callbackId": callbackId
        };
        NSArray *payload = @[message];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        if (!jsonData.length) {
            [strongSelf addLog:@"RPC 发送失败：请求序列化异常"];
            return;
        }
        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSString *url = strongSelf.manorH5Url.length ? strongSelf.manorH5Url : @"https://66666674.h5app.alipay.com/www/index.html";
        if ([bridge respondsToSelector:@selector(_doFlushMessageQueue:url:)]) {
            [strongSelf.flushLock lock];
            [bridge _doFlushMessageQueue:json url:url];
            [strongSelf.flushLock unlock];
        }
    };

    if ([NSThread isMainThread]) sendBlock();
    else dispatch_async(dispatch_get_main_queue(), sendBlock);
}

- (void)executeManorScriptOnWebView:(NSString *)script {
    if (!script.length) return;
    __weak typeof(self) weakSelf = self;
    void (^runBlock)(void) = ^{
        AntManorManager *strongSelf = weakSelf;
        if (!strongSelf.manorBridge) return;
        id contentView = [strongSelf.manorBridge respondsToSelector:@selector(contentView)] ? strongSelf.manorBridge.contentView : nil;
        id webView = nil;
        if ([contentView respondsToSelector:@selector(webView)]) webView = ((id (*)(id, SEL))objc_msgSend)(contentView, @selector(webView));
        if (!webView && [strongSelf.manorBridge respondsToSelector:@selector(webView)]) {
            webView = ((id (*)(id, SEL))objc_msgSend)(strongSelf.manorBridge, @selector(webView));
        }
        if ([webView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(webView, @selector(evaluateJavaScript:completionHandler:), script, nil);
        }
    };
    if ([NSThread isMainThread]) runBlock();
    else dispatch_async(dispatch_get_main_queue(), runBlock);
}

#pragma mark - 日志

- (void)addLog:(NSString *)message {
    if (!message.length) return;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@", [formatter stringFromDate:[NSDate date]], message];
    @synchronized (self.logRecord) {
        [self.logRecord addObject:line];
        while (self.logRecord.count > 300) {
            [self.logRecord removeObjectAtIndex:0];
        }
    }
    NSLog(@"[AntManorPort] %@", message);
}

- (void)recordStage:(NSString *)stage {
    [self addLog:stage];
}

#pragma mark - 每日任务缓存

- (void)loadFoodDoneState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *today = ManorDateString();
    NSString *savedDate = [defaults stringForKey:kManorFoodDoneDateKey];
    if ([savedDate isEqualToString:today]) {
        NSArray *saved = [defaults arrayForKey:kManorFoodDoneListKey] ?: @[];
        self.foodDoneTasks = [NSMutableSet setWithArray:saved];
        NSArray *savedPots = [defaults arrayForKey:kManorManureDoneListKey] ?: @[];
        self.manureDonePots = [NSMutableSet setWithArray:savedPots];
    } else {
        self.foodDoneTasks = [NSMutableSet set];
        self.manureDonePots = [NSMutableSet set];
        [defaults setObject:today forKey:kManorFoodDoneDateKey];
        [defaults setObject:@[] forKey:kManorFoodDoneListKey];
        [defaults setObject:@[] forKey:kManorManureDoneListKey];
    }
    self.foodDoneDate = today;
}

- (void)saveFoodDoneState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.foodDoneDate ?: ManorDateString() forKey:kManorFoodDoneDateKey];
    [defaults setObject:[self.foodDoneTasks allObjects] forKey:kManorFoodDoneListKey];
    [defaults setObject:[self.manureDonePots allObjects] forKey:kManorManureDoneListKey];
    [defaults synchronize];
}

#pragma mark - 自动化

- (void)checkAndRunManorAutomations {
    if (!self.enableAutoManor) return;
    if (!self.manorBridge) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastAutomationCheckTime < 15.0) return;
    self.lastAutomationCheckTime = now;

    [self recordStage:@"蚂蚁庄园：执行日常自动化体检..."];
    [self signManorDaily];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self answerManorClassroomQuestion];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self collectManorChickenManure];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3200 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self feedManorChickenIfNeeded];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4000 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self queryManorFarmTasks];
    });
    if (self.enableFamilyIntimacy && self.intimacy.rankConfigured && now - self.lastRankQueryTime >= 600.0) {
        self.lastRankQueryTime = now;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5000 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            [self.intimacy queryRank];
        });
    }
}

- (void)signManorDaily {
    if (!self.enableAutoManor) return;
    NSString *today = ManorDateString();
    NSString *lastSignDate = [[NSUserDefaults standardUserDefaults] stringForKey:@"manor_last_sign_date"];
    if ([lastSignDate isEqualToString:today]) return;

    [self recordStage:@"蚂蚁庄园：今日未签到，提交签到请求（180g 饲料）..."];
    [self sendManorRPC:@"com.alipay.antfarm.sign"
             requestData:@[@{@"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5", @"version": @"1.8.2302070202.46"}]
          callbackPrefix:@"manor_sign_"];
    [[NSUserDefaults standardUserDefaults] setObject:today forKey:@"manor_last_sign_date"];
}

- (void)answerManorClassroomQuestion {
    if (!self.enableAutoManor) return;
    NSString *today = ManorDateString();
    NSString *lastAnswerDate = [[NSUserDefaults standardUserDefaults] stringForKey:@"manor_last_answer_date"];
    if ([lastAnswerDate isEqualToString:today]) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastAnswerAttemptTime < 30.0) return;
    self.lastAnswerAttemptTime = now;

    [self recordStage:@"蚂蚁庄园：尝试自动完成庄园小课堂答题..."];
    [self executeManorScriptOnWebView:[self classroomAnswerScript]];
}

- (void)queryManorFarmTasks {
    if (!self.enableAutoManor) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastTaskQueryTime < 60.0) return;
    self.lastTaskQueryTime = now;
    [self recordStage:@"蚂蚁庄园：拉取任务列表（只读）..."];
    [self sendManorRPC:@"com.alipay.antfarm.listFarmTask"
             requestData:@[@{@"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5", @"version": @"1.8.2302070202.46"}]
          callbackPrefix:@"manor_tasks_"];
}

- (void)feedManorChickenIfNeeded {
    if (!self.enableAutoManor) return;
    if (self.isManorChickenEating) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastFeedTime < 60.0) return;
    if (self.lastManorFoodStock < 180) {
        if (now - self.lastFeedWarnTime >= 600.0) {
            self.lastFeedWarnTime = now;
            [self recordStage:[NSString stringWithFormat:@"蚂蚁庄园：饲料不足 180g（当前 %ldg），暂不投喂", (long)self.lastManorFoodStock]];
        }
        return;
    }
    self.lastFeedTime = now;

    [self recordStage:@"蚂蚁庄园：小鸡饭盆空闲，提交投喂请求（180g）..."];
    [self sendManorRPC:@"com.alipay.antfarm.feedAnimal"
             requestData:@[@{
                 @"animalType": @"CHICK",
                 @"canMock": @YES,
                 @"farmId": self.lastManorFarmId ?: @"",
                 @"requestType": @"NORMAL",
                 @"sceneCode": @"ANTFARM",
                 @"source": @"H5",
                 @"version": @"1.8.2302070202.46"
             }]
          callbackPrefix:@"manor_feed_"];
}

- (void)collectManorChickenManure {
    if (!self.enableAutoManor) return;
    NSString *today = ManorDateString();
    if ([self.lastManorManureCollectDate isEqualToString:today]) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastManureCollectTime < 15.0) return;
    self.lastManureCollectTime = now;

    [self executeManorScriptOnWebView:@"(()=>{try{"
     "function c(el){if(!el)return;try{el.click();}catch(e){}}"
     "const all=Array.from(document.querySelectorAll('*'));"
     "for(const el of all){"
     "  const t=(el.innerText||el.getAttribute('aria-label')||'').trim();"
     "  if(t.includes('肥料')||el.className?.includes?.('manure')){c(el);break;}"
     "}"
     "}catch(e){}})();"];
}

- (void)collectManorChickenManurePot:(NSString *)potNo {
    if (!potNo.length) return;
    [self sendManorRPC:@"com.alipay.antfarm.collectManurePot"
             requestData:@[@{@"manurePotNOs": potNo, @"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5", @"version": @"1.8.2302070202.46"}]
          callbackPrefix:@"manor_manure_"];
}

#pragma mark - 回包处理

- (void)handleManorResponse:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return;

    @try {
        NSDictionary *resData = ManorPayloadFromResponse(dict);

        // 亲密度观测（无论自动任务开关与否，只记录解析到的事实数据）
        [self.intimacy observeResponse:dict];

        // 普通庄园自动化
        NSDictionary *subFarm = nil;
        NSDictionary *ownAnimal = nil;
        if (self.enableAutoManor) {
            subFarm = [resData[@"subFarmVO"] isKindOfClass:NSDictionary.class] ? resData[@"subFarmVO"] : nil;
            ownAnimal = [resData[@"ownAnimal"] isKindOfClass:NSDictionary.class] ? resData[@"ownAnimal"] : nil;
            if (subFarm || ownAnimal) {
                [self handleFarmState:resData subFarm:subFarm ownAnimal:ownAnimal];
            }

            NSDictionary *signDict = [resData[@"signList"] isKindOfClass:NSDictionary.class] ? resData[@"signList"] : nil;
            if (signDict) [self handleSignState:signDict];

            NSArray *taskList = [resData[@"farmTaskList"] isKindOfClass:NSArray.class] ? resData[@"farmTaskList"] : nil;
            if (taskList.count) {
                [self handleFoodTaskList:taskList];
            }
        }

        NSArray *taskList = [resData[@"farmTaskList"] isKindOfClass:NSArray.class] ? resData[@"farmTaskList"] : nil;
        if (self.enableFamilyIntimacy && taskList.count) {
            [self.intimacy handleTaskList:taskList source:@"farm"];
        }

        // 家庭/亲密度任务列表：不同活动命名不一致，统一尝试识别
        if (self.enableFamilyIntimacy) {
            [self scanFamilyPayload:resData depth:0];
            if (resData != dict) [self scanFamilyPayload:dict depth:0];
        }

        id bubbleConfig = resData[@"bubbleConfig"] ?: dict[@"bubbleConfig"];
        NSString *opType = ManorString(dict[@"operationType"] ?: (resData[@"operationType"] ?: self.lastRpcOperationType));
        if (self.enableAutoManor && [bubbleConfig isKindOfClass:NSDictionary.class]) {
            NSString *bubbleType = ManorString(bubbleConfig[@"bubbleType"]);
            if ([bubbleType isEqualToString:@"NEW_DAILY_MANURE"]) {
                NSDictionary *dailyManure = [resData[@"dailyManure"] isKindOfClass:NSDictionary.class] ? resData[@"dailyManure"] : nil;
                BOOL canCollect = dailyManure ? [dailyManure[@"canCollect"] boolValue] : YES;
                if (!canCollect) {
                    self.lastManorManureCollectDate = ManorDateString();
                } else if (![self.lastManorManureCollectDate isEqualToString:ManorDateString()]) {
                    [self collectManorChickenManure];
                }
            }
        }

        if (self.enableAutoManor && [opType containsString:@"feedAnimal"]) {
            self.isManorChickenEating = YES;
            NSInteger stock = ManorInteger(resData[@"foodStock"]);
            if (stock > 0) self.lastManorFoodStock = stock;
            [self recordStage:@"蚂蚁庄园：小鸡投喂成功"];
        }
        if (self.enableAutoManor && [opType containsString:@"receiveFarmTaskAward"]) {
            NSInteger addFood = ManorInteger(resData[@"haveAddFoodStock"]);
            NSInteger stock = ManorInteger(resData[@"foodStock"]);
            if (stock > 0) self.lastManorFoodStock = stock;
            if (addFood > 0) {
                [self recordStage:[NSString stringWithFormat:@"蚂蚁庄园：领取饲料 +%ldg（当前 %ldg）", (long)addFood, (long)self.lastManorFoodStock]];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[AntManorPort] handleManorResponse exception: %@", exception);
    }
}

- (void)scanFamilyPayload:(id)payload depth:(NSInteger)depth {
    if (depth > 3) return;
    if ([payload isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = payload;
        for (NSString *key in @[@"familyTaskList", @"familyActivityTaskList", @"activityTaskList", @"intimacyTaskList", @"homeTaskList"]) {
            id list = dict[key];
            if ([list isKindOfClass:NSArray.class] && [list count] > 0) {
                [self.intimacy handleTaskList:list source:@"family"];
            }
        }
        for (NSString *key in @[@"familyActivity", @"familyInfo", @"familyVO", @"intimacyInfo", @"familyRankInfo", @"intimacyRankInfo"]) {
            id info = dict[key];
            if ([info isKindOfClass:NSDictionary.class]) {
                [self.intimacy observeResponse:info];
            }
        }
        for (id value in dict.allValues) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
                [self scanFamilyPayload:value depth:depth + 1];
            }
        }
    } else if ([payload isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)payload) {
            if ([item isKindOfClass:NSDictionary.class] || [item isKindOfClass:NSArray.class]) {
                [self scanFamilyPayload:item depth:depth + 1];
            }
        }
    }
}

- (void)handleFarmState:(NSDictionary *)resData subFarm:(NSDictionary *)subFarm ownAnimal:(NSDictionary *)ownAnimal {
    [self loadFoodDoneState];
    if (subFarm[@"farmId"]) self.lastManorFarmId = ManorString(subFarm[@"farmId"]);
    else if (ownAnimal[@"farmId"]) self.lastManorFarmId = ManorString(ownAnimal[@"farmId"]);
    else if (ownAnimal[@"masterFarmId"]) self.lastManorFarmId = ManorString(ownAnimal[@"masterFarmId"]);

    NSArray *animals = [subFarm[@"animals"] isKindOfClass:NSArray.class] ? subFarm[@"animals"] : nil;
    for (NSDictionary *animal in animals) {
        if (![animal isKindOfClass:NSDictionary.class]) continue;
        if (animal[@"animalId"]) {
            self.lastManorAnimalId = ManorString(animal[@"animalId"]);
            break;
        }
    }
    if (!self.lastManorAnimalId.length && ownAnimal[@"animalId"]) {
        self.lastManorAnimalId = ManorString(ownAnimal[@"animalId"]);
    }

    if (subFarm[@"foodStock"] != nil) self.lastManorFoodStock = ManorInteger(subFarm[@"foodStock"]);
    else if (resData[@"foodStock"] != nil) self.lastManorFoodStock = ManorInteger(resData[@"foodStock"]);

    NSInteger foodStockLimit = ManorInteger(subFarm[@"foodStockLimit"]);
    if (foodStockLimit <= 0) foodStockLimit = ManorInteger(resData[@"foodStockLimit"]);
    if (foodStockLimit > 0) self.lastManorFoodStockLimit = foodStockLimit;

    NSInteger foodInTrough = ManorInteger(subFarm[@"foodInTrough"]);
    NSInteger foodLimit = ManorInteger(subFarm[@"foodInTroughLimit"]);
    if (foodLimit <= 0) foodLimit = 180;
    NSInteger countdown = ManorInteger(subFarm[@"countdown"]);
    BOOL eating = (foodInTrough >= foodLimit) || (countdown > 0 && foodInTrough > 0);
    self.isManorChickenEating = eating;

    NSDictionary *manureVO = [subFarm[@"manureVO"] isKindOfClass:NSDictionary.class] ? subFarm[@"manureVO"] : nil;
    NSArray *pots = [manureVO[@"manurePotList"] isKindOfClass:NSArray.class] ? manureVO[@"manurePotList"] : nil;
    if (!self.manureDonePots) self.manureDonePots = [NSMutableSet set];
    for (NSDictionary *pot in pots) {
        if (![pot isKindOfClass:NSDictionary.class]) continue;
        NSString *potNo = ManorString(pot[@"manurePotNO"]);
        NSInteger amount = ManorInteger(pot[@"manurePotNum"]);
        if (potNo.length && amount >= 100 && ![self.manureDonePots containsObject:potNo]) {
            [self.manureDonePots addObject:potNo];
            [self saveFoodDoneState];
            [self recordStage:[NSString stringWithFormat:@"蚂蚁庄园：收取肥料（%ldg）", (long)amount]];
            [self collectManorChickenManurePot:potNo];
        }
    }

    if (!eating && self.lastManorFoodStock >= 180) {
        [self feedManorChickenIfNeeded];
    }
}

- (void)handleSignState:(NSDictionary *)signDict {
    NSArray *signs = [signDict[@"signList"] isKindOfClass:NSArray.class] ? signDict[@"signList"] : nil;
    NSString *today = ManorDateString();
    NSInteger continuous = 0;
    for (NSDictionary *sign in signs) {
        if (![sign isKindOfClass:NSDictionary.class]) continue;
        if ([ManorString(sign[@"signKey"]) isEqualToString:today] && [sign[@"signed"] boolValue]) {
            [[NSUserDefaults standardUserDefaults] setObject:today forKey:@"manor_last_sign_date"];
        }
        NSInteger days = ManorInteger(sign[@"currentContinuousCount"]);
        if (days > continuous) continuous = days;
    }
    if (continuous > 0) {
        static NSInteger lastLoggedDays = 0;
        if (lastLoggedDays != continuous) {
            lastLoggedDays = continuous;
            [self recordStage:[NSString stringWithFormat:@"蚂蚁庄园：今日已连续签到 %ld 天", (long)continuous]];
        }
    }
}

- (void)handleFoodTaskList:(NSArray *)taskList {
    [self loadFoodDoneState];
    NSInteger currentStock = self.lastManorFoodStock;
    NSInteger limit = self.lastManorFoodStockLimit > 0 ? self.lastManorFoodStockLimit : 1800;

    for (NSDictionary *task in taskList) {
        if (![task isKindOfClass:NSDictionary.class]) continue;
        NSString *bizKey = ManorString(task[@"bizKey"]);
        NSString *taskId = ManorString(task[@"taskId"]);
        NSString *status = [ManorString(task[@"taskStatus"]) uppercaseString];
        NSString *title = ManorString(task[@"title"]);
        NSString *mode = [ManorString(task[@"taskMode"]) uppercaseString];
        NSString *category = ManorString(task[@"categorizationSecondLevel"]);
        NSString *desc = ManorString(task[@"taskDesc"] ?: task[@"desc"]);
        NSInteger award = ManorInteger(task[@"awardCount"]);

        if (!title.length) title = bizKey.length ? bizKey : taskId;
        if (!bizKey.length) continue;

        if ([status isEqualToString:@"RECEIVED"] || [status isEqualToString:@"ALREADY_RECEIVED"]) {
            if ([bizKey isEqualToString:@"ANSWER"]) {
                [[NSUserDefaults standardUserDefaults] setObject:ManorDateString() forKey:@"manor_last_answer_date"];
            }
            continue;
        }

        if ([status isEqualToString:@"FINISHED"] || [status isEqualToString:@"WAIT_RECEIVE"]) {
            if (!taskId.length) continue;
            if (limit > 0 && (currentStock >= limit || currentStock + award > limit)) {
                continue;
            }
            NSString *claimKey = [@"claim:" stringByAppendingString:taskId];
            if (![self.foodDoneTasks containsObject:claimKey]) {
                [self.foodDoneTasks addObject:claimKey];
                currentStock += award;
                self.lastManorFoodStock = currentStock;
                [self saveFoodDoneState];
                [self.intimacy markExternallySubmittedTask:task source:@"farm"];
                [self recordStage:[NSString stringWithFormat:@"蚂蚁庄园：领取已完成任务“%@”（%ldg）", title, (long)award]];
                [self sendManorRPC:@"com.alipay.antfarm.receiveFarmTaskAward"
                         requestData:@[@{@"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5", @"taskId": taskId, @"version": @"1.8.2302070202.46"}]
                      callbackPrefix:@"manor_claim_"];
            }
            continue;
        }

        if (![status isEqualToString:@"TODO"]) continue;
        if ([bizKey isEqualToString:@"ANSWER"]) {
            [self answerManorClassroomQuestion];
            continue;
        }
        // 需真实出资/授权/游戏充值的任务一律不自动执行
        if ([category isEqualToString:@"Public_Welfare_Behavior"] ||
            [category isEqualToString:@"Game"] || [category isEqualToString:@"Game_Charge"] ||
            [bizKey containsString:@"DONATE"] || [bizKey containsString:@"DONATION"] ||
            [bizKey containsString:@"PAY"] || [bizKey containsString:@"PURCHASE"] ||
            [desc containsString:@"捐"] || [desc containsString:@"付款"] || [desc containsString:@"支付"] || [desc containsString:@"实付"]) {
            continue;
        }
        if (!([mode isEqualToString:@"VIEW"] || [mode isEqualToString:@"TRIGGER"])) continue;

        NSString *taskKey = [@"do:" stringByAppendingString:bizKey];
        if ([self.foodDoneTasks containsObject:taskKey]) continue;
        [self.foodDoneTasks addObject:taskKey];
        [self saveFoodDoneState];
        [self.intimacy markExternallySubmittedTask:task source:@"farm"];
        [self recordStage:[NSString stringWithFormat:@"蚂蚁庄园：完成浏览任务“%@”", title]];
        [self sendManorRPC:@"com.alipay.antfarm.doFarmTask"
                 requestData:@[@{@"bizKey": bizKey, @"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5", @"version": @"1.8.2302070202.46"}]
              callbackPrefix:@"manor_task_"];
    }
}

#pragma mark - 庄园小课堂答题脚本

- (NSString *)classroomAnswerScript {
    return @"(()=>{try{"
     "const QA=["
     "{k:'退避三舍',a:'九十里'},{k:'烂醉如泥',a:'一种虫子'},{k:'宣笔',a:'宣州'},{k:'秋冻',a:'并不是'},"
     "{k:'企鹅有翅膀',a:'有'},{k:'奶皮',a:'脂肪和蛋白质'},{k:'猫咪胡子',a:'感知'},{k:'美轮美奂',a:'高大华美'},"
     "{k:'弱冠',a:'20岁'},{k:'执子之手',a:'战友情'},{k:'忘忧草',a:'萱草'},{k:'目无全牛',a:'技艺'},"
     "{k:'小鸡也是有耳朵',a:'当然有'},{k:'促织',a:'蟋蟀'},{k:'东道主',a:'方向'},{k:'单腿站立',a:'减少热量'},"
     "{k:'海中霸王',a:'虎鲸'},{k:'司空见惯',a:'官职'},{k:'生辰八字',a:'八个字'},{k:'初出茅庐',a:'草房'},"
     "{k:'立夏',a:'夏季'},{k:'兰亭序',a:'王羲之'},{k:'向日葵成熟后头',a:'花盘太重'},{k:'蹴鞠',a:'足球'},"
     "{k:'小鸡的羽毛能防水',a:'不能'},{k:'纨绔子弟',a:'细绢'},{k:'电热毯',a:'睡前关闭'},{k:'五花八门',a:'兵法'},"
     "{k:'海中牛奶',a:'牡蛎'},{k:'七月流火',a:'恒星'},{k:'六艺',a:'驾驭'},{k:'海星有眼睛',a:'有'},"
     "{k:'逆风',a:'增加升力'},{k:'炙手可热',a:'权势'},{k:'三秋',a:'三个季度'},{k:'三宝殿',a:'佛教'},"
     "{k:'吃小石子',a:'帮助消化'},{k:'花中君子',a:'竹'},{k:'千金小姐',a:'男'},{k:'打哈欠',a:'真会'},"
     "{k:'冰皮月饼',a:'不用烘烤'},{k:'落汤鸡',a:'尾脂腺'},{k:'信手拈来',a:'随手'},{k:'骨骼数量',a:'会'},"
     "{k:'弄璋',a:'男孩'},{k:'弄瓦',a:'女孩'},{k:'汗流浃背',a:'大臣'},{k:'梁上君子',a:'窃贼'},"
     "{k:'银子',a:'并不是'},{k:'蜗牛',a:'黏液'},{k:'吃太咸',a:'多喝水'},{k:'昙花一现',a:'晚上'},"
     "{k:'兔子眼睛',a:'血液'},{k:'藕断丝连',a:'导管'},{k:'金榜题名',a:'进士'},{k:'阳春白雪',a:'高雅'},"
     "{k:'下里巴人',a:'民间'},{k:'桃李满天下',a:'学生'},{k:'白发三千丈',a:'夸张'},{k:'红娘',a:'西厢记'},"
     "{k:'豆蔻年华',a:'13'},{k:'及笄',a:'15'},{k:'而立',a:'30'},{k:'不惑',a:'40'},"
     "{k:'知天命',a:'50'},{k:'耳顺',a:'60'},{k:'古稀',a:'70'},{k:'期颐',a:'100'},"
     "{k:'文房四宝',a:'笔墨纸砚'},{k:'岁寒三友',a:'松竹梅'},{k:'出水芙蓉',a:'荷花'},{k:'国色天香',a:'牡丹'},"
     "{k:'破釜沉舟',a:'巨鹿'},{k:'草船借箭',a:'赤壁'},{k:'负荆请罪',a:'廉颇'},{k:'完璧归赵',a:'蔺相如'},"
     "{k:'望梅止渴',a:'曹操'},{k:'三顾茅庐',a:'刘备'},{k:'指鹿为马',a:'赵高'},{k:'四面楚歌',a:'项羽'},"
     "{k:'背水一战',a:'韩信'},{k:'煮豆燃萁',a:'曹植'},{k:'入木三分',a:'王羲之'},{k:'闻鸡起舞',a:'祖逖'},"
     "{k:'程门立雪',a:'杨时'},{k:'东施效颦',a:'西施'},{k:'守株待兔',a:'侥幸'},{k:'掩耳盗铃',a:'自欺欺人'},"
     "{k:'拔苗助长',a:'急于求成'},{k:'刻舟求剑',a:'拘泥'},{k:'滥竽充数',a:'南郭先生'},{k:'买椟还珠',a:'取舍不当'},"
     "{k:'杯弓蛇影',a:'疑神疑鬼'},{k:'狐假虎威',a:'借别人威势'}"
     "];"
     "function tap(el){if(!el)return;try{el.click();}catch(e){}}"
     "const claim=Array.from(document.querySelectorAll('button,a,[role=\"button\"],[class*=\"btn\"],div,span'))"
     "  .find(el=>{const t=(el.innerText||'').trim();return t==='去领取'||t==='开心收下'||t==='领取饲料'||t==='我知道了';});"
     "if(claim){tap(claim);return;}"
     "let qText='';let qEl=null;"
     "for(const el of document.querySelectorAll('*')){"
     "  if(el.children.length===0){"
     "    const t=(el.innerText||'').trim();"
     "    if((t.includes('？')||t.includes('?')||t.includes('下列')||t.includes('考考你'))&&t.length>=6&&t.length<=120){qText=t;qEl=el;break;}"
     "  }"
     "}"
     "if(!qText)return;"
     "const box=qEl.closest('[class*=\"content\"],[class*=\"modal\"],[class*=\"dialog\"],[class*=\"card\"],div')||document.body;"
     "const opts=[];const seen=new Set();"
     "for(const el of box.querySelectorAll('button,[role=\"button\"],[class*=\"option\"],[class*=\"answer\"],[class*=\"btn\"],div')){"
     "  if(el.children.length>2)continue;"
     "  const t=(el.innerText||'').trim();"
     "  if(!t||t===qText||t.length>35)continue;"
     "  if(t.includes('小课堂')||t.includes('饲料')||t.includes('知道了')||t.includes('规则'))continue;"
     "  const r=el.getBoundingClientRect();"
     "  if(r.width>40&&r.height>18&&r.height<140&&!seen.has(t)){seen.add(t);opts.push({el,t});}"
     "}"
     "if(opts.length<2||opts.length>4)return;"
     "const hit=QA.find(x=>qText.includes(x.k));"
     "let target=null;"
     "if(hit)target=opts.find(o=>o.t.includes(hit.a)||hit.a.includes(o.t));"
     "if(!target)target=opts.find(o=>o.t.includes('正确')||o.t.includes('是的')||o.t.includes('可以')||o.t.includes('有'))||opts[0];"
     "if(target)tap(target.el);"
     "}catch(e){}})();";
}

@end
