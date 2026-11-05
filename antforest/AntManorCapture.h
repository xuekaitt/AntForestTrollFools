//
//  AntManorCapture.h
//  AntManorPort
//
//  本地调试抓包：记录 H5 页面与插件经 PSDJsBridge 收发的 RPC。
//  仅写入 App 沙盒 Documents/AntManor，不联网、不上传。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AntManorCapture : NSObject

// 默认开启，可用面板开关或 manor_capture_enabled 覆盖
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *message);

@property (nonatomic, assign, readonly) NSInteger recordCount;
@property (nonatomic, assign, readonly) NSInteger familyCandidateCount;
@property (nonatomic, assign, readonly) unsigned long long currentFileSize;
@property (nonatomic, copy, readonly) NSString *currentFilePath;
@property (nonatomic, copy, readonly) NSString *familyCandidatesPath;

+ (instancetype)sharedInstance;

// message 可为 NSString JSON、NSArray 或 NSDictionary（_doFlushMessageQueue:url: 的原始参数）
- (void)recordRequestMessage:(nullable id)message url:(nullable id)url;
// response 为 transformResponseData: 的原始回包
- (void)recordResponse:(nullable id)response url:(nullable id)url;

// 开启抓包并在 duration 秒后自动关闭；completion 在主线程回调
- (void)startTimedCapture:(NSTimeInterval)duration completion:(nullable void (^)(void))completion;

// 当前会话已生成的文件（可能包含滚动文件）
- (NSArray<NSURL *> *)exportFileURLs;
// 便于提示/复制的路径描述；没有文件时返回目录路径
- (NSString *)exportPathDescription;

@end

NS_ASSUME_NONNULL_END
