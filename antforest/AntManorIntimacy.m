//
//  AntManorIntimacy.m
//  AntManorPort
//

#import "AntManorIntimacy.h"

static NSString *const kIntimacyDailyDateKey = @"manor_intimacy_daily_date";
static NSString *const kIntimacyDailyGainedKey = @"manor_intimacy_daily_gained";
static NSString *const kIntimacyDailyTasksKey = @"manor_intimacy_daily_tasks";
static NSString *const kIntimacyDailyRequestsKey = @"manor_intimacy_daily_requests";
static NSString *const kIntimacyDailySubmittedKey = @"manor_intimacy_daily_submitted";
static NSString *const kIntimacyLastRequestKey = @"manor_intimacy_last_request_ts";
static NSString *const kIntimacyLastRankKey = @"manor_intimacy_last_rank";
static NSString *const kIntimacyLastRankTotalKey = @"manor_intimacy_last_rank_total";

static NSString *ManorIntimacyToday(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd";
    });
    return [formatter stringFromDate:[NSDate date]];
}

static NSString *ManorIntimacyStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSInteger ManorIntimacyIntegerValue(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value integerValue];
    return 0;
}

@interface AntManorIntimacy ()
@property (nonatomic, strong) NSMutableSet<NSString *> *todaySubmittedKeys;
@property (nonatomic, assign) NSTimeInterval lastRequestTime;
@property (nonatomic, strong) NSMutableSet<NSString *> *notifiedMissingKeys;
@end

@implementation AntManorIntimacy

+ (instancetype)sharedInstance {
    static AntManorIntimacy *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AntManorIntimacy alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _todaySubmittedKeys = [NSMutableSet set];
        _notifiedMissingKeys = [NSMutableSet set];
        _dailyTaskLimit = 10;
        _dailyIntimacyCap = 0;
        _minRequestInterval = 45.0;
        _topNThreshold = 2000000;
        _activityStartDate = @"";
        _activityEndDate = @"";
        _familyTaskOperationType = @"";
        _familyTaskRequestDataJSON = @"";
        _familyTaskClaimOperationType = @"";
        _familyTaskClaimRequestDataJSON = @"";
        _rankOperationType = @"";
        _rankRequestDataJSON = @"";
        _statusNote = @"";
        _lastRankText = @"";
        [self reloadConfig];
        [self resetDailyIfNeeded];
    }
    return self;
}

#pragma mark - 配置

- (NSString *)configPath {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [[documents stringByAppendingPathComponent:@"AntManor"] stringByAppendingPathComponent:@"manor-config.json"];
}

- (void)reloadConfig {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *fileConfig = nil;
    NSString *path = [self configPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) fileConfig = json;
    }
    if (!fileConfig) {
        [self notifyMissingOnce:@"config-file" message:[NSString stringWithFormat:@"亲密度配置缺失：请在 %@ 放置 manor-config.json", path]];
    }

    _activityEnabled = [self boolFromConfig:fileConfig defaults:defaults key:@"activityEnabled" fallback:NO];
    _activityStartDate = [self stringFromConfig:fileConfig defaults:defaults key:@"activityStartDate" fallback:@""];
    _activityEndDate = [self stringFromConfig:fileConfig defaults:defaults key:@"activityEndDate" fallback:@""];
    _dailyTaskLimit = [self integerFromConfig:fileConfig defaults:defaults key:@"dailyTaskLimit" fallback:10];
    _dailyIntimacyCap = [self integerFromConfig:fileConfig defaults:defaults key:@"dailyIntimacyCap" fallback:0];
    _minRequestInterval = [self doubleFromConfig:fileConfig defaults:defaults key:@"minRequestInterval" fallback:45.0];
    _topNThreshold = [self integerFromConfig:fileConfig defaults:defaults key:@"topNThreshold" fallback:2000000];
    _familyTaskOperationType = [self stringFromConfig:fileConfig defaults:defaults key:@"familyTaskOperationType" fallback:@""];
    _familyTaskRequestDataJSON = [self stringFromConfig:fileConfig defaults:defaults key:@"familyTaskRequestData" fallback:@""];
    _familyTaskClaimOperationType = [self stringFromConfig:fileConfig defaults:defaults key:@"familyTaskClaimOperationType" fallback:@""];
    _familyTaskClaimRequestDataJSON = [self stringFromConfig:fileConfig defaults:defaults key:@"familyTaskClaimRequestData" fallback:@""];
    _rankOperationType = [self stringFromConfig:fileConfig defaults:defaults key:@"rankOperationType" fallback:@""];
    _rankRequestDataJSON = [self stringFromConfig:fileConfig defaults:defaults key:@"rankRequestData" fallback:@""];

    if (_dailyTaskLimit < 1) _dailyTaskLimit = 1;
    if (_minRequestInterval < 10.0) _minRequestInterval = 10.0;
    if (_topNThreshold < 1) _topNThreshold = 2000000;

    if (!_activityEnabled) {
        self.statusNote = [NSString stringWithFormat:@"亲密度自动化未启用（activityEnabled=false，配置：%@）", path];
    } else if (!_rankOperationType.length) {
        self.statusNote = [NSString stringWithFormat:@"排名接口未配置（需抓包），配置：%@", path];
    } else {
        self.statusNote = @"排名接口已配置";
    }
}

- (BOOL)boolFromConfig:(NSDictionary *)config defaults:(NSUserDefaults *)defaults key:(NSString *)key fallback:(BOOL)fallback {
    id override = [defaults objectForKey:[@"manor_cfg_" stringByAppendingString:key]];
    if (override) return [override boolValue];
    id value = config[key];
    return value ? [value boolValue] : fallback;
}

- (NSString *)stringFromConfig:(NSDictionary *)config defaults:(NSUserDefaults *)defaults key:(NSString *)key fallback:(NSString *)fallback {
    id override = [defaults objectForKey:[@"manor_cfg_" stringByAppendingString:key]];
    if (override) return ManorIntimacyStringValue(override);
    id value = config[key];
    return value ? ManorIntimacyStringValue(value) : fallback;
}

- (NSInteger)integerFromConfig:(NSDictionary *)config defaults:(NSUserDefaults *)defaults key:(NSString *)key fallback:(NSInteger)fallback {
    id override = [defaults objectForKey:[@"manor_cfg_" stringByAppendingString:key]];
    if (override) return ManorIntimacyIntegerValue(override);
    id value = config[key];
    return value ? ManorIntimacyIntegerValue(value) : fallback;
}

- (double)doubleFromConfig:(NSDictionary *)config defaults:(NSUserDefaults *)defaults key:(NSString *)key fallback:(double)fallback {
    id override = [defaults objectForKey:[@"manor_cfg_" stringByAppendingString:key]];
    if (override) return [override doubleValue];
    id value = config[key];
    return value ? [value doubleValue] : fallback;
}

#pragma mark - 每日状态

- (void)resetDailyIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *today = ManorIntimacyToday();
    NSString *savedDate = [defaults stringForKey:kIntimacyDailyDateKey];
    if (![savedDate isEqualToString:today]) {
        [defaults setObject:today forKey:kIntimacyDailyDateKey];
        [defaults setInteger:0 forKey:kIntimacyDailyGainedKey];
        [defaults setInteger:0 forKey:kIntimacyDailyTasksKey];
        [defaults setInteger:0 forKey:kIntimacyDailyRequestsKey];
        [defaults setObject:@[] forKey:kIntimacyDailySubmittedKey];
        [defaults synchronize];
        [self.todaySubmittedKeys removeAllObjects];
        [self.notifiedMissingKeys removeAllObjects];
        _todayGainedIntimacy = 0;
        _todayTaskCount = 0;
        _todayRequestCount = 0;
        _lastRequestTime = 0;
        return;
    }
    _todayGainedIntimacy = [defaults integerForKey:kIntimacyDailyGainedKey];
    _todayTaskCount = [defaults integerForKey:kIntimacyDailyTasksKey];
    _todayRequestCount = [defaults integerForKey:kIntimacyDailyRequestsKey];
    _lastRequestTime = [defaults doubleForKey:kIntimacyLastRequestKey];
    NSArray *submitted = [defaults arrayForKey:kIntimacyDailySubmittedKey] ?: @[];
    if (!self.todaySubmittedKeys.count) {
        self.todaySubmittedKeys = [NSMutableSet setWithArray:submitted];
    }
}

- (void)saveDailyState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.todayGainedIntimacy forKey:kIntimacyDailyGainedKey];
    [defaults setInteger:self.todayTaskCount forKey:kIntimacyDailyTasksKey];
    [defaults setInteger:self.todayRequestCount forKey:kIntimacyDailyRequestsKey];
    [defaults setObject:[self.todaySubmittedKeys allObjects] forKey:kIntimacyDailySubmittedKey];
    [defaults setDouble:self.lastRequestTime forKey:kIntimacyLastRequestKey];
    [defaults synchronize];
}

#pragma mark - 活动期

- (BOOL)activityActive {
    if (!self.activityEnabled) return NO;
    NSString *today = ManorIntimacyToday();
    if (self.activityStartDate.length && [today compare:self.activityStartDate] == NSOrderedAscending) return NO;
    if (self.activityEndDate.length && [today compare:self.activityEndDate] == NSOrderedDescending) return NO;
    return YES;
}

- (BOOL)rankConfigured {
    return self.rankOperationType.length > 0;
}

#pragma mark - 任务识别

- (NSString *)taskIdentifierForTask:(NSDictionary *)task {
    if (![task isKindOfClass:NSDictionary.class]) return @"";
    for (NSString *key in @[@"taskId", @"taskIdValue", @"bizKey", @"iepTaskId", @"taskType", @"title"]) {
        NSString *value = ManorIntimacyStringValue(task[key]);
        if (value.length) return value;
    }
    return @"";
}

static NSString *ManorTaskText(NSDictionary *task) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"bizKey", @"taskType", @"title", @"desc", @"taskDesc", @"awardName", @"awardType", @"sceneCode", @"category", @"categorizationSecondLevel"]) {
        NSString *value = ManorIntimacyStringValue(task[key]);
        if (value.length) [parts addObject:value];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSInteger ManorTaskExpectedIntimacy(NSDictionary *task) {
    for (NSString *key in @[@"intimacy", @"intimacyCount", @"intimacyAward", @"awardIntimacy", @"addIntimacy"]) {
        id value = task[key];
        NSInteger amount = ManorIntimacyIntegerValue(value);
        if (amount > 0) return amount;
    }
    return 0;
}

static BOOL ManorTaskLooksLikeIntimacy(NSDictionary *task, NSString *source) {
    NSString *text = [ManorTaskText(task) lowercaseString];
    if ([text containsString:@"亲密度"] || [text containsString:@"intimacy"]) return YES;
    if ([source isEqualToString:@"family"]) return YES;
    if ([text containsString:@"家庭"] && ([text containsString:@"任务"] || [text containsString:@"活动"])) return YES;
    if ([text containsString:@"family"] && ([text containsString:@"task"] || [text containsString:@"activity"])) return YES;
    return ManorTaskExpectedIntimacy(task) > 0;
}

static NSString *ManorTaskStatus(NSDictionary *task) {
    for (NSString *key in @[@"taskStatus", @"status", @"taskState"]) {
        NSString *value = [ManorIntimacyStringValue(task[key]) uppercaseString];
        if (value.length) return value;
    }
    return @"";
}

#pragma mark - 任务执行

- (void)handleTaskList:(NSArray *)taskList source:(NSString *)source {
    if (!self.activityEnabled) return;
    [self resetDailyIfNeeded];
    if (!self.activityActive) {
        [self notifyMissingOnce:@"activity-window" message:@"亲密度活动未在配置的活动期内，跳过家庭任务"];
        return;
    }
    if (![taskList isKindOfClass:NSArray.class]) return;

    NSInteger matched = 0;
    for (id item in taskList) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *task = item;
        if (!ManorTaskLooksLikeIntimacy(task, source)) continue;
        matched += 1;
        NSString *status = ManorTaskStatus(task);
        if ([status isEqualToString:@"RECEIVED"] || [status isEqualToString:@"ALREADY_RECEIVED"] || [status isEqualToString:@"COMPLETED"]) continue;
        if ([status isEqualToString:@"FINISHED"] || [status isEqualToString:@"WAIT_RECEIVE"] || [status isEqualToString:@"WAIT_RECEIVE_AWARD"]) {
            [self claimTask:task source:source];
            continue;
        }
        [self submitTask:task source:source];
    }
    if (matched == 0) {
        [self notifyMissingOnce:[@"no-task-" stringByAppendingString:ManorIntimacyToday()]
                        message:@"未在该任务列表中识别到亲密度任务（若活动页无任务列表，需抓包确认家庭任务接口）"];
    }
}

- (BOOL)canSubmitTask:(NSDictionary *)task source:(NSString *)source {
    if (!self.activityEnabled || !self.activityActive) return NO;
    [self resetDailyIfNeeded];

    NSString *status = ManorTaskStatus(task);
    if (status.length &&
        ![status isEqualToString:@"TODO"] &&
        ![status isEqualToString:@"PENDING"] &&
        ![status isEqualToString:@"UNKNOWN"] &&
        ![status isEqualToString:@"INIT"]) {
        return NO;
    }

    if (self.todayTaskCount >= self.dailyTaskLimit) return NO;
    if (self.todayRequestCount >= self.dailyTaskLimit * 2) return NO;
    if (self.dailyIntimacyCap > 0 && self.todayGainedIntimacy >= self.dailyIntimacyCap) return NO;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (self.lastRequestTime > 0 && (now - self.lastRequestTime) < self.minRequestInterval) return NO;

    NSString *identifier = [self taskIdentifierForTask:task];
    if (!identifier.length) return NO;
    NSString *key = [NSString stringWithFormat:@"%@:%@", source, identifier];
    return ![self.todaySubmittedKeys containsObject:key];
}

- (void)submitTask:(NSDictionary *)task source:(NSString *)source {
    if (![self canSubmitTask:task source:source]) return;

    NSString *identifier = [self taskIdentifierForTask:task];
    NSString *key = [NSString stringWithFormat:@"%@:%@", source, identifier];
    NSString *operationType = nil;
    NSArray *requestData = nil;

    if ([source isEqualToString:@"family"]) {
        if (!self.familyTaskOperationType.length) {
            [self notifyMissingOnce:@"family-op" message:@"家庭亲密度任务执行接口未配置（familyTaskOperationType），需抓包后填入本地配置"];
            return;
        }
        NSString *template = self.familyTaskRequestDataJSON;
        if (!template.length) {
            [self notifyMissingOnce:@"family-template" message:@"家庭任务请求体模板未配置（familyTaskRequestData），需按抓包结果填入"];
            return;
        }
        operationType = self.familyTaskOperationType;
        requestData = [self requestDataFromTemplate:template task:task];
        if (!requestData) {
            [self notifyMissingOnce:@"family-template-invalid" message:@"家庭任务请求体模板不是合法 JSON 数组"];
            return;
        }
    } else {
        // 复用项目已验证的庄园任务接口
        operationType = @"com.alipay.antfarm.doFarmTask";
        NSString *bizKey = ManorIntimacyStringValue(task[@"bizKey"]);
        if (!bizKey.length) bizKey = identifier;
        requestData = @[@{
            @"bizKey": bizKey,
            @"requestType": @"NORMAL",
            @"sceneCode": @"ANTFARM",
            @"source": @"H5",
            @"version": @"1.8.2302070202.46"
        }];
    }

    [self markSubmittedKey:key countTask:YES];
    [self log:[NSString stringWithFormat:@"提交亲密度任务：%@（来源 %@，第 %ld/%ld 个）", identifier, source, (long)self.todayTaskCount, (long)self.dailyTaskLimit]];
    if (self.requestHandler) {
        self.requestHandler(operationType, requestData, @"manor_intimacy_task_");
    } else {
        [self log:@"亲密度任务发送失败：RPC 通道未就绪"];
    }
}

- (void)claimTask:(NSDictionary *)task source:(NSString *)source {
    NSString *identifier = [self taskIdentifierForTask:task];
    if (!identifier.length) return;
    NSString *claimKey = [NSString stringWithFormat:@"claim:%@:%@", source, identifier];
    if ([self.todaySubmittedKeys containsObject:claimKey]) return;
    if (self.dailyIntimacyCap > 0 && self.todayGainedIntimacy >= self.dailyIntimacyCap) return;

    NSString *operationType = nil;
    NSArray *requestData = nil;
    if ([source isEqualToString:@"family"]) {
        if (!self.familyTaskClaimOperationType.length) {
            [self notifyMissingOnce:@"family-claim-op" message:@"家庭任务领奖接口未配置（familyTaskClaimOperationType），需抓包后填入本地配置"];
            return;
        }
        operationType = self.familyTaskClaimOperationType;
        NSString *template = self.familyTaskClaimRequestDataJSON;
        if (template.length) {
            requestData = [self requestDataFromTemplate:template task:task];
        }
        if (!requestData) {
            requestData = @[@{@"taskId": identifier, @"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5"}];
        }
    } else {
        operationType = @"com.alipay.antfarm.receiveFarmTaskAward";
        requestData = @[@{@"taskId": identifier, @"requestType": @"NORMAL", @"sceneCode": @"ANTFARM", @"source": @"H5"}];
    }

    [self markSubmittedKey:claimKey countTask:NO];
    [self log:[NSString stringWithFormat:@"领取亲密度任务奖励：%@（来源 %@）", identifier, source]];
    if (self.requestHandler) {
        self.requestHandler(operationType, requestData, @"manor_intimacy_claim_");
    }
}

- (NSArray *)requestDataFromTemplate:(NSString *)template task:(NSDictionary *)task {
    NSString *bizKey = ManorIntimacyStringValue(task[@"bizKey"]);
    NSString *taskId = [self taskIdentifierForTask:task];
    NSString *activityId = ManorIntimacyStringValue(task[@"activityId"]);
    NSString *taskType = ManorIntimacyStringValue(task[@"taskType"]);
    NSString *filled = template;
    filled = [filled stringByReplacingOccurrencesOfString:@"{{bizKey}}" withString:bizKey];
    filled = [filled stringByReplacingOccurrencesOfString:@"{{taskId}}" withString:taskId];
    filled = [filled stringByReplacingOccurrencesOfString:@"{{activityId}}" withString:activityId];
    filled = [filled stringByReplacingOccurrencesOfString:@"{{taskType}}" withString:taskType];
    NSData *data = [filled dataUsingEncoding:NSUTF8StringEncoding];
    id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [json isKindOfClass:NSArray.class] ? json : nil;
}

- (void)markSubmittedKey:(NSString *)key countTask:(BOOL)countTask {
    [self.todaySubmittedKeys addObject:key];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    self.lastRequestTime = now;
    self.todayRequestCount += 1;
    if (countTask) self.todayTaskCount += 1;
    [self saveDailyState];
}

- (void)markExternallySubmittedTask:(NSDictionary *)task source:(NSString *)source {
    NSString *identifier = [self taskIdentifierForTask:task];
    if (!identifier.length) return;
    [self.todaySubmittedKeys addObject:[NSString stringWithFormat:@"%@:%@", source, identifier]];
    [self.todaySubmittedKeys addObject:[NSString stringWithFormat:@"claim:%@:%@", source, identifier]];
    [self saveDailyState];
}

#pragma mark - 响应解析

- (void)observeResponse:(NSDictionary *)response {
    if (![response isKindOfClass:NSDictionary.class]) return;
    [self resetDailyIfNeeded];

    NSInteger gained = [self intimacyGainInDictionary:response depth:0];
    if (gained > 0) {
        self.todayGainedIntimacy += gained;
        [self saveDailyState];
        [self log:[NSString stringWithFormat:@"识别到亲密度 +%ld，今日累计 %ld", (long)gained, (long)self.todayGainedIntimacy]];
    }

    NSDictionary *rankInfo = [self rankInfoInDictionary:response depth:0];
    if (rankInfo) {
        NSInteger rank = [self rankValueInDictionary:rankInfo keys:@[@"myRank", @"intimacyRank", @"rankNo", @"rankNum", @"rank"] depth:0];
        NSInteger total = [self rankValueInDictionary:rankInfo keys:@[@"totalRankNum", @"totalRankCount", @"familyMemberCount", @"rankTotal", @"totalCount"] depth:0];
        if (rank > 0) {
            self.lastRank = rank;
            if (total > 0) self.lastRankTotal = total;
            self.lastRankText = total > 0
                ? [NSString stringWithFormat:@"第 %ld 名 / 共 %ld", (long)rank, (long)total]
                : [NSString stringWithFormat:@"第 %ld 名", (long)rank];
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setInteger:rank forKey:kIntimacyLastRankKey];
            [defaults setInteger:total forKey:kIntimacyLastRankTotalKey];
            [defaults synchronize];
            [self log:[NSString stringWithFormat:@"亲密度排名更新：%@（%@前 %ld 名）", self.lastRankText,
                       self.lastRankInTopN ? @"处于" : @"未进入",
                       (long)self.topNThreshold]];
        }
    }
}

- (NSInteger)intimacyGainInDictionary:(NSDictionary *)dict depth:(NSInteger)depth {
    if (![dict isKindOfClass:NSDictionary.class] || depth > 4) return 0;
    for (NSString *key in @[@"addIntimacy", @"intimacyAdd", @"gainedIntimacy", @"intimacyGain", @"addIntimacyValue", @"todayAddIntimacy"]) {
        NSInteger value = ManorIntimacyIntegerValue(dict[key]);
        if (value > 0) return value;
    }
    for (id value in dict.allValues) {
        if ([value isKindOfClass:NSDictionary.class]) {
            NSInteger nested = [self intimacyGainInDictionary:value depth:depth + 1];
            if (nested > 0) return nested;
        } else if ([value isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)value) {
                if ([item isKindOfClass:NSDictionary.class]) {
                    NSInteger nested = [self intimacyGainInDictionary:item depth:depth + 1];
                    if (nested > 0) return nested;
                }
            }
        }
    }
    return 0;
}

- (NSDictionary *)rankInfoInDictionary:(NSDictionary *)dict depth:(NSInteger)depth {
    if (![dict isKindOfClass:NSDictionary.class] || depth > 4) return nil;
    for (NSString *key in @[@"familyRankInfo", @"familyRankVO", @"intimacyRankInfo", @"rankInfo", @"rankVO"]) {
        id value = dict[key];
        if ([value isKindOfClass:NSDictionary.class]) return value;
    }
    if (dict[@"myRank"] || dict[@"intimacyRank"]) return dict;
    for (id value in dict.allValues) {
        if ([value isKindOfClass:NSDictionary.class]) {
            NSDictionary *nested = [self rankInfoInDictionary:value depth:depth + 1];
            if (nested) return nested;
        } else if ([value isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)value) {
                if ([item isKindOfClass:NSDictionary.class]) {
                    NSDictionary *nested = [self rankInfoInDictionary:item depth:depth + 1];
                    if (nested) return nested;
                }
            }
        }
    }
    return nil;
}

- (NSInteger)rankValueInDictionary:(NSDictionary *)dict keys:(NSArray *)keys depth:(NSInteger)depth {
    if (![dict isKindOfClass:NSDictionary.class] || depth > 3) return 0;
    for (NSString *key in keys) {
        NSInteger value = ManorIntimacyIntegerValue(dict[key]);
        if (value > 0) return value;
    }
    for (id value in dict.allValues) {
        if ([value isKindOfClass:NSDictionary.class]) {
            NSInteger nested = [self rankValueInDictionary:value keys:keys depth:depth + 1];
            if (nested > 0) return nested;
        }
    }
    return 0;
}

- (BOOL)lastRankInTopN {
    return self.lastRank > 0 && self.lastRank <= self.topNThreshold;
}

#pragma mark - 排名查询

- (void)queryRank {
    if (!self.rankConfigured) {
        [self notifyMissingOnce:@"rank-op" message:@"排名查询未执行：rankOperationType 未配置（需抓包获得接口名）"];
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (self.lastRequestTime > 0 && (now - self.lastRequestTime) < self.minRequestInterval) {
        [self log:@"排名查询过于频繁，已节流"];
        return;
    }
    self.lastRequestTime = now;
    self.todayRequestCount += 1;
    [self saveDailyState];

    NSArray *requestData = @[];
    if (self.rankRequestDataJSON.length) {
        id json = [NSJSONSerialization JSONObjectWithData:[self.rankRequestDataJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([json isKindOfClass:NSArray.class]) requestData = json;
        else [self notifyMissingOnce:@"rank-template" message:@"rankRequestData 不是合法 JSON 数组，已按空请求体发送"];
    }
    [self log:@"请求亲密度排名..."];
    if (self.requestHandler) {
        self.requestHandler(self.rankOperationType, requestData, @"manor_intimacy_rank_");
    } else {
        [self log:@"排名查询发送失败：RPC 通道未就绪"];
    }
}

#pragma mark - 展示

- (NSArray<NSString *> *)summaryLines {
    [self resetDailyIfNeeded];
    NSString *window = @"未配置活动期";
    if (self.activityStartDate.length || self.activityEndDate.length) {
        window = [NSString stringWithFormat:@"%@ ~ %@", self.activityStartDate.length ? self.activityStartDate : @"?", self.activityEndDate.length ? self.activityEndDate : @"?"];
    }
    NSString *cap = self.dailyIntimacyCap > 0 ? [NSString stringWithFormat:@"%ld", (long)self.dailyIntimacyCap] : @"未配置";
    NSString *rank = self.lastRankText.length ? self.lastRankText : @"未查询";
    NSString *topN = self.lastRank > 0
        ? (self.lastRankInTopN ? [NSString stringWithFormat:@"是（前 %ld 名）", (long)self.topNThreshold]
                              : [NSString stringWithFormat:@"否（前 %ld 名外）", (long)self.topNThreshold])
        : @"未知";

    return @[
        [NSString stringWithFormat:@"活动期：%@（%@）", window, self.activityActive ? @"进行中" : @"未激活"],
        [NSString stringWithFormat:@"今日亲密度：+%ld / 上限 %@", (long)self.todayGainedIntimacy, cap],
        [NSString stringWithFormat:@"今日任务：%ld/%ld，请求 %ld 次", (long)self.todayTaskCount, (long)self.dailyTaskLimit, (long)self.todayRequestCount],
        [NSString stringWithFormat:@"排名：%@", rank],
        [NSString stringWithFormat:@"前 %ld 万名：%@", (long)self.topNThreshold, topN],
        [NSString stringWithFormat:@"状态：%@", self.statusNote.length ? self.statusNote : @"待运行"],
    ];
}

#pragma mark - 辅助

- (void)log:(NSString *)message {
    if (!message.length) return;
    NSLog(@"[AntManorPort] %@", message);
    if (self.logHandler) self.logHandler(message);
}

- (void)notifyMissingOnce:(NSString *)key message:(NSString *)message {
    if (!key.length) key = message;
    @synchronized (self.notifiedMissingKeys) {
        if ([self.notifiedMissingKeys containsObject:key]) return;
        [self.notifiedMissingKeys addObject:key];
    }
    [self log:message];
}

@end
