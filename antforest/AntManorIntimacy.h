//
//  AntManorIntimacy.h
//  AntManorPort
//
//  蚂蚁庄园「家庭」活动期亲密度模块
//  接口未抓包确认的部分一律留空，由本地配置注入，避免凭空请求。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AntManorIntimacy : NSObject

@property (nonatomic, copy, readonly) NSString *configPath;

// 活动期与节流
@property (nonatomic, assign) BOOL activityEnabled;
@property (nonatomic, copy) NSString *activityStartDate;   // yyyy-MM-dd
@property (nonatomic, copy) NSString *activityEndDate;     // yyyy-MM-dd
@property (nonatomic, assign) NSInteger dailyTaskLimit;     // 每日最多执行任务数
@property (nonatomic, assign) NSInteger dailyIntimacyCap;   // 每日可得亲密度上限，0 表示未配置
@property (nonatomic, assign) NSTimeInterval minRequestInterval; // 两次任务请求最小间隔（秒）
@property (nonatomic, assign) NSInteger topNThreshold;      // 默认 2000000

// 接口配置（未抓包确认的保持为空字符串）
@property (nonatomic, copy) NSString *familyTaskOperationType;
@property (nonatomic, copy) NSString *familyTaskRequestDataJSON;   // 支持 {{bizKey}} {{taskId}} {{activityId}} {{taskType}}
@property (nonatomic, copy) NSString *familyTaskClaimOperationType;
@property (nonatomic, copy) NSString *familyTaskClaimRequestDataJSON;
@property (nonatomic, copy) NSString *rankOperationType;
@property (nonatomic, copy) NSString *rankRequestDataJSON;

// 今日进度
@property (nonatomic, assign) NSInteger todayGainedIntimacy;
@property (nonatomic, assign) NSInteger todayTaskCount;
@property (nonatomic, assign) NSInteger todayRequestCount;
@property (nonatomic, assign, readonly) BOOL activityActive;
@property (nonatomic, assign, readonly) BOOL rankConfigured;

// 排名结果
@property (nonatomic, assign) NSInteger lastRank;
@property (nonatomic, assign) NSInteger lastRankTotal;
@property (nonatomic, copy) NSString *lastRankText;
@property (nonatomic, assign, readonly) BOOL lastRankInTopN;
@property (nonatomic, copy) NSString *statusNote;

// 家庭页下发的真实观测值（来源：抓包 180020380000000271/familyFeed.html）
@property (nonatomic, assign) NSInteger observedActivityIntimacy;   // familyActivityIntimateNumber
@property (nonatomic, assign) NSInteger observedFamilyDailyIntimacy; // familyDailyIntimateNumber
@property (nonatomic, copy) NSString *observedActivityWindowText;   // activityInfo 起止日期
@property (nonatomic, copy) NSString *observedRankGearText;         // 排名线（前 N 名所需亲密度）
@property (nonatomic, copy) NSString *observedFamilyTaskText;       // familyTasks 概览

// 由 AntManorManager 注入的能力
@property (nonatomic, copy, nullable) void (^requestHandler)(NSString *operationType, NSArray *requestData, NSString *callbackPrefix);
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *message);

+ (instancetype)sharedInstance;

- (void)reloadConfig;
- (void)resetDailyIfNeeded;

// 任务处理（source: farm / family）
- (void)handleTaskList:(NSArray *)taskList source:(NSString *)source;
- (BOOL)canSubmitTask:(NSDictionary *)task source:(NSString *)source;
- (void)submitTask:(NSDictionary *)task source:(NSString *)source;
// 庄园主流程已提交/领取过的任务，标记后避免亲密度模块重复请求
- (void)markExternallySubmittedTask:(NSDictionary *)task source:(NSString *)source;

- (void)observeResponse:(NSDictionary *)response;
- (void)queryRank;

- (NSArray<NSString *> *)summaryLines;
- (NSString *)taskIdentifierForTask:(NSDictionary *)task;

@end

NS_ASSUME_NONNULL_END
