//
//  AntManorManager.h
//  AntManorPort
//
//  仅保留蚂蚁庄园能力的桥接、请求与自动化管理。
//  蚂蚁森林/芭芭农场/神奇海洋等模块已移除。
//

#import <Foundation/Foundation.h>
#import "PSDJsBridge.h"
#import "AntManorIntimacy.h"

NS_ASSUME_NONNULL_BEGIN

@interface AntManorManager : NSObject

@property (nonatomic, weak, nullable) PSDJsBridge *manorBridge;
@property (nonatomic, copy) NSString *manorH5Url;
@property (nonatomic, assign) BOOL enableAutoManor;
@property (nonatomic, assign) BOOL enableFamilyIntimacy;
@property (nonatomic, copy) NSString *lastRpcOperationType;
@property (nonatomic, copy) NSString *lastManorFarmId;
@property (nonatomic, copy) NSString *lastManorAnimalId;
@property (nonatomic, copy) NSString *lastManorManureCollectDate;
@property (nonatomic, assign) BOOL isManorChickenEating;
@property (nonatomic, assign) NSInteger lastManorFoodStock;
@property (nonatomic, assign) NSInteger lastManorFoodStockLimit;
@property (nonatomic, strong) NSMutableArray<NSString *> *logRecord;
@property (nonatomic, strong, readonly) AntManorIntimacy *intimacy;

+ (instancetype)sharedInstance;

+ (BOOL)isManorURL:(nullable NSURL *)url;
+ (BOOL)isManorResponse:(nullable id)value;

- (void)registerManorBridge:(id)bridge url:(nullable NSString *)url;
- (void)checkAndRunManorAutomations;
- (void)handleManorResponse:(NSDictionary *)dict;
- (void)sendManorRPC:(NSString *)operationType
          requestData:(NSArray *)requestData
       callbackPrefix:(NSString *)callbackPrefix;
- (void)executeManorScriptOnWebView:(NSString *)script;
- (NSString *)effectiveUrlForBridge:(nullable id)bridge;

- (void)addLog:(NSString *)message;
- (void)recordStage:(NSString *)stage;

@end

NS_ASSUME_NONNULL_END
