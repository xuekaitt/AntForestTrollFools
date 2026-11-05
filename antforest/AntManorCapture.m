//
//  AntManorCapture.m
//  AntManorPort
//

#import "AntManorCapture.h"

static NSString *const kManorCaptureEnabledKey = @"manor_capture_enabled";
static const unsigned long long kManorCaptureMaxBytes = 5ULL * 1024 * 1024;
static const NSUInteger kManorCaptureMaxFiles = 10;
static const NSUInteger kManorCandidateMaxFiles = 5;
static const NSInteger kManorCaptureMaxString = 500;
static const NSInteger kManorCaptureMaxDepth = 8;
static const NSUInteger kManorCaptureMaxItems = 100;
static const NSUInteger kManorCaptureMaxKeys = 120;
static const NSUInteger kManorCaptureMaxHighlights = 30;

typedef enum ManorSensitiveKind {
    ManorSensitiveNone = 0,
    ManorSensitiveToken,
    ManorSensitivePhone,
    ManorSensitiveIDCard,
    ManorSensitiveBankCard,
    ManorSensitiveUserID,
    ManorSensitiveEmail,
    ManorSensitiveRealName,
    ManorSensitiveAddress
} ManorSensitiveKind;

#pragma mark - 基础工具

static NSDateFormatter *ManorCaptureISODateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone localTimeZone];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    });
    return formatter;
}

static NSDateFormatter *ManorCaptureFileDateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone localTimeZone];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
    });
    return formatter;
}

static NSString *ManorCaptureText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    if ([value isKindOfClass:NSURL.class]) return [(NSURL *)value absoluteString];
    if ([value isKindOfClass:NSDate.class]) return [ManorCaptureISODateFormatter() stringFromDate:value];
    return value ? [value description] : @"";
}

static NSString *ManorCaptureTruncate(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    if (value.length <= kManorCaptureMaxString) return value;
    return [NSString stringWithFormat:@"%@...[truncated,len=%lu]", [value substringToIndex:kManorCaptureMaxString], (unsigned long)value.length];
}

static NSString *ManorCaptureStars(NSUInteger count) {
    NSMutableString *stars = [NSMutableString stringWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [stars appendString:@"*"];
    return stars;
}

static NSString *ManorCaptureMaskMiddle(NSString *value, NSUInteger prefix, NSUInteger suffix) {
    NSString *text = ManorCaptureText(value);
    if (!text.length) return text;
    if (text.length <= prefix + suffix) return ManorCaptureStars(text.length);
    NSUInteger starCount = text.length - prefix - suffix;
    return [NSString stringWithFormat:@"%@%@%@",
            [text substringToIndex:prefix],
            ManorCaptureStars(starCount),
            [text substringFromIndex:text.length - suffix]];
}

static BOOL ManorCaptureAllDigits(NSString *value) {
    if (!value.length) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

static BOOL ManorCaptureLooksLikePhone(NSString *value) {
    if (value.length != 11 || !ManorCaptureAllDigits(value)) return NO;
    unichar first = [value characterAtIndex:0];
    unichar second = [value characterAtIndex:1];
    return first == '1' && second >= '3' && second <= '9';
}

static BOOL ManorCaptureLooksLikeIDCard(NSString *value) {
    if (value.length == 18) {
        NSString *head = [value substringToIndex:17];
        if (!ManorCaptureAllDigits(head)) return NO;
        unichar last = [[value uppercaseString] characterAtIndex:17];
        return (last >= '0' && last <= '9') || last == 'X';
    }
    if (value.length == 15) return ManorCaptureAllDigits(value);
    return NO;
}

static ManorSensitiveKind ManorCaptureKindForKey(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length) return ManorSensitiveNone;
    NSString *normalized = [[[key lowercaseString]
                              stringByReplacingOccurrencesOfString:@"_" withString:@""]
                             stringByReplacingOccurrencesOfString:@"-" withString:@""];

    for (NSString *token in @[@"token", @"cookie", @"session", @"authorization", @"password",
                              @"passwd", @"secret", @"privatekey", @"ticket", @"credential",
                              @"signature", @"signvalue", @"securitytoken", @"logintoken"]) {
        if ([normalized containsString:token]) return ManorSensitiveToken;
    }
    if ([normalized isEqualToString:@"sign"]) return ManorSensitiveToken;
    for (NSString *phone in @[@"phone", @"mobile", @"telephone", @"telno", @"mobileno", @"phoneno", @"cellphone"]) {
        if ([normalized containsString:phone]) return ManorSensitivePhone;
    }
    for (NSString *card in @[@"idcard", @"idno", @"certno", @"identityno", @"identitycard", @"certificate"]) {
        if ([normalized containsString:card]) return ManorSensitiveIDCard;
    }
    for (NSString *bank in @[@"bankcard", @"bankaccount", @"accountno", @"cardno", @"payaccount"]) {
        if ([normalized containsString:bank]) return ManorSensitiveBankCard;
    }
    for (NSString *uid in @[@"userid", @"alipayuserid", @"openid", @"memberid", @"customerid",
                            @"accountid", @"loginid", @"useraccount"]) {
        if ([normalized containsString:uid]) return ManorSensitiveUserID;
    }
    if ([normalized isEqualToString:@"uid"]) return ManorSensitiveUserID;
    for (NSString *mail in @[@"email", @"mailaddress"]) {
        if ([normalized containsString:mail]) return ManorSensitiveEmail;
    }
    for (NSString *name in @[@"realname", @"truename", @"holdername"]) {
        if ([normalized containsString:name]) return ManorSensitiveRealName;
    }
    for (NSString *address in @[@"address", @"shippingaddress", @"homeaddress"]) {
        if ([normalized containsString:address]) return ManorSensitiveAddress;
    }
    return ManorSensitiveNone;
}

static NSString *ManorCaptureMaskString(NSString *value, ManorSensitiveKind kind) {
    NSString *text = ManorCaptureText(value);
    if (!text.length) return text;

    if (kind == ManorSensitiveNone) {
        if (ManorCaptureLooksLikePhone(text)) kind = ManorSensitivePhone;
        else if (ManorCaptureLooksLikeIDCard(text)) kind = ManorSensitiveIDCard;
    }

    NSString *masked = text;
    switch (kind) {
        case ManorSensitiveToken:
            masked = @"[REDACTED]";
            break;
        case ManorSensitivePhone:
            masked = ManorCaptureMaskMiddle(text, 3, 4);
            break;
        case ManorSensitiveIDCard:
            masked = ManorCaptureMaskMiddle(text, 4, 4);
            break;
        case ManorSensitiveBankCard: {
            NSString *tail = text.length > 4 ? [text substringFromIndex:text.length - 4] : text;
            masked = [NSString stringWithFormat:@"**** %@", tail];
            break;
        }
        case ManorSensitiveUserID:
            masked = ManorCaptureMaskMiddle(text, 2, 2);
            break;
        case ManorSensitiveEmail: {
            NSRange atRange = [text rangeOfString:@"@"];
            if (atRange.location != NSNotFound) {
                NSString *local = [text substringToIndex:atRange.location];
                NSString *domain = [text substringFromIndex:atRange.location];
                NSString *head = local.length ? [local substringToIndex:1] : @"";
                masked = [NSString stringWithFormat:@"%@***%@", head, domain];
            } else {
                masked = ManorCaptureMaskMiddle(text, 1, 2);
            }
            break;
        }
        case ManorSensitiveRealName: {
            NSString *head = text.length ? [text substringToIndex:1] : @"";
            masked = [NSString stringWithFormat:@"%@**", head];
            break;
        }
        case ManorSensitiveAddress: {
            masked = text.length > 6 ? [NSString stringWithFormat:@"%@******", [text substringToIndex:6]] : @"******";
            break;
        }
        default:
            break;
    }
    return ManorCaptureTruncate(masked);
}

static id ManorSanitizeValue(id value, NSInteger depth, ManorSensitiveKind inheritedKind) {
    if (depth > kManorCaptureMaxDepth) return @"[depth-limit]";
    if (value == nil || [value isKindOfClass:NSNull.class]) return [NSNull null];

    if ([value isKindOfClass:NSString.class]) {
        return ManorCaptureMaskString((NSString *)value, inheritedKind);
    }
    if ([value isKindOfClass:NSNumber.class]) {
        if (inheritedKind != ManorSensitiveNone) {
            return ManorCaptureMaskString([(NSNumber *)value stringValue], inheritedKind);
        }
        return value;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSArray *array = value;
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:MIN(array.count, kManorCaptureMaxItems)];
        NSUInteger limit = MIN(array.count, kManorCaptureMaxItems);
        for (NSUInteger i = 0; i < limit; i++) {
            [result addObject:ManorSanitizeValue(array[i], depth + 1, ManorSensitiveNone)];
        }
        if (array.count > limit) {
            [result addObject:[NSString stringWithFormat:@"...[truncated,%lu items]", (unsigned long)(array.count - limit)]];
        }
        return result;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = value;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:MIN(dictionary.count, kManorCaptureMaxKeys)];
        __block NSUInteger added = 0;
        NSArray *keys = dictionary.allKeys;
        for (id rawKey in keys) {
            if (added >= kManorCaptureMaxKeys) break;
            NSString *key = ManorCaptureText(rawKey);
            if (!key.length) key = @"(non-string-key)";
            ManorSensitiveKind keyKind = ManorCaptureKindForKey(key);
            ManorSensitiveKind childKind = keyKind;
            if (inheritedKind == ManorSensitiveToken && childKind == ManorSensitiveNone) {
                childKind = ManorSensitiveToken;
            }
            result[key] = ManorSanitizeValue(dictionary[rawKey], depth + 1, childKind);
            added++;
        }
        if (dictionary.count > added) {
            result[@"__truncated__"] = [NSString stringWithFormat:@"%lu keys omitted", (unsigned long)(dictionary.count - added)];
        }
        return result;
    }
    if ([value isKindOfClass:NSData.class]) {
        return [NSString stringWithFormat:@"[NSData %lu bytes]", (unsigned long)[(NSData *)value length]];
    }
    return ManorCaptureTruncate(ManorCaptureText(value));
}

static NSString *ManorSanitizeURLString(id url) {
    if (!url) return @"";
    NSString *text = ManorCaptureText(url);
    if (!text.length) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithString:text];
    if (components) {
        if (components.user.length) components.user = @"***";
        if (components.password.length) components.password = @"***";
        if (components.queryItems.count) {
            NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithCapacity:components.queryItems.count];
            for (NSURLQueryItem *item in components.queryItems) {
                if (ManorCaptureKindForKey(item.name) != ManorSensitiveNone) {
                    [items addObject:[NSURLQueryItem queryItemWithName:item.name value:@"***"]];
                } else {
                    [items addObject:item];
                }
            }
            components.queryItems = items;
        }
        text = components.string ?: text;
    }
    return ManorCaptureTruncate(text);
}

static NSString *ManorFindStringValue(id value, NSString *key, NSInteger depth) {
    if (!value || depth > 5) return nil;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = value;
        id direct = dict[key];
        if ([direct isKindOfClass:NSString.class] && [(NSString *)direct length]) return direct;
        if ([direct isKindOfClass:NSNumber.class]) return [(NSNumber *)direct stringValue];
        for (id child in dict.allValues) {
            if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
                NSString *found = ManorFindStringValue(child, key, depth + 1);
                if (found.length) return found;
            }
        }
    } else if ([value isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)value) {
            NSString *found = ManorFindStringValue(child, key, depth + 1);
            if (found.length) return found;
        }
    }
    return nil;
}

static NSString *ManorOperationType(id value) {
    return ManorFindStringValue(value, @"operationType", 0);
}

static NSDictionary *ManorResponseSummary(id original, id sanitized) {
    if ([sanitized isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = sanitized;
        NSArray *topKeys = dict.allKeys;
        NSString *wrapperName = @"none";
        NSDictionary *wrapper = nil;
        for (NSString *name in @[@"resData", @"data", @"result"]) {
            id value = dict[name];
            if ([value isKindOfClass:NSDictionary.class]) {
                wrapperName = name;
                wrapper = value;
                break;
            }
        }
        NSArray *wrapperKeys = wrapper ? wrapper.allKeys : topKeys;
        NSMutableDictionary *highlights = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"operationType", @"resultCode", @"resultStatus", @"success",
                                @"errorCode", @"errorMsg", @"memo", @"responseId", @"callbackId"]) {
            id value = dict[key];
            if (value && ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])) {
                highlights[key] = value;
            }
        }
        if (wrapper) {
            for (NSString *key in wrapper.allKeys) {
                if (highlights.count >= kManorCaptureMaxHighlights) break;
                id value = wrapper[key];
                if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) {
                    highlights[key] = value;
                }
            }
        }
        return @{
            @"topKeys": topKeys ?: @[],
            @"wrapper": wrapperName,
            @"wrapperKeys": wrapperKeys ?: @[],
            @"highlights": highlights,
        };
    }
    if ([sanitized isKindOfClass:NSArray.class]) {
        return @{
            @"topKeys": @[],
            @"wrapper": @"array",
            @"itemCount": @([(NSArray *)sanitized count]),
            @"highlights": @{},
        };
    }
    return @{
        @"topKeys": @[],
        @"wrapper": @"scalar",
        @"highlights": @{@"value": sanitized ?: [NSNull null]},
    };
}

static void ManorScanFamilyKeywords(id value, NSInteger depth, NSMutableSet<NSString *> *matches) {
    if (!value || depth > 6 || matches.count >= 5) return;
    NSArray<NSString *> *keywords = @[@"family", @"intimacy", @"亲密度", @"hometask", @"activity"];

    if ([value isKindOfClass:NSString.class]) {
        NSString *haystack = [(NSString *)value lowercaseString];
        if (haystack.length > 2000) haystack = [haystack substringToIndex:2000];
        for (NSString *keyword in keywords) {
            if ([haystack containsString:keyword]) [matches addObject:keyword];
        }
        return;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        for (id rawKey in ((NSDictionary *)value).allKeys) {
            NSString *key = [ManorCaptureText(rawKey) lowercaseString];
            for (NSString *keyword in keywords) {
                if ([key containsString:keyword]) [matches addObject:keyword];
            }
            ManorScanFamilyKeywords(((NSDictionary *)value)[rawKey], depth + 1, matches);
            if (matches.count >= 5) return;
        }
        return;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSArray *array = value;
        NSUInteger limit = MIN(array.count, kManorCaptureMaxItems);
        for (NSUInteger i = 0; i < limit; i++) {
            ManorScanFamilyKeywords(array[i], depth + 1, matches);
            if (matches.count >= 5) return;
        }
    }
}

static NSArray<NSString *> *ManorFamilyMatches(id payload, NSString *operationType) {
    NSMutableSet<NSString *> *matches = [NSMutableSet set];
    ManorScanFamilyKeywords(payload, 0, matches);
    ManorScanFamilyKeywords(operationType, 0, matches);
    return [[matches allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

#pragma mark - NDJSON 文件流

@interface ManorCaptureStream : NSObject
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *baseName;
@property (nonatomic, assign) BOOL timestamped;
@property (nonatomic, assign) NSUInteger maxFiles;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, assign) NSInteger recordCount;
@property (nonatomic, strong) NSMutableArray<NSString *> *sessionPaths;
@end

@implementation ManorCaptureStream

- (instancetype)initWithDirectory:(NSString *)directory baseName:(NSString *)baseName timestamped:(BOOL)timestamped maxFiles:(NSUInteger)maxFiles {
    self = [super init];
    if (self) {
        _directory = [directory copy];
        _baseName = [baseName copy];
        _timestamped = timestamped;
        _maxFiles = maxFiles;
        _sessionPaths = [NSMutableArray array];
    }
    return self;
}

- (NSString *)nextPath {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDate *now = [NSDate date];
    NSString *stamp = [ManorCaptureFileDateFormatter() stringFromDate:now];
    NSUInteger suffix = 1;
    while (suffix < 1000) {
        NSString *name = nil;
        if (self.timestamped) {
            name = suffix == 1
                ? [NSString stringWithFormat:@"%@-%@.ndjson", self.baseName, stamp]
                : [NSString stringWithFormat:@"%@-%@-%lu.ndjson", self.baseName, stamp, (unsigned long)suffix];
        } else {
            name = suffix == 1
                ? [NSString stringWithFormat:@"%@.ndjson", self.baseName]
                : [NSString stringWithFormat:@"%@-%lu.ndjson", self.baseName, (unsigned long)suffix];
        }
        NSString *candidate = [self.directory stringByAppendingPathComponent:name];
        if (![manager fileExistsAtPath:candidate]) return candidate;
        suffix++;
    }
    return [self.directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.ndjson", self.baseName, stamp]];
}

- (void)closeFile {
    if (!self.handle) return;
    @try {
        [self.handle closeFile];
    } @catch (NSException *exception) {
    }
    self.handle = nil;
}

- (BOOL)openNewFile {
    [self closeFile];
    NSString *path = [self nextPath];
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0644)};
    BOOL created = [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:attributes];
    if (!created) return NO;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return NO;
    self.handle = handle;
    self.path = path;
    self.size = 0;
    [self.sessionPaths addObject:path];
    [self pruneOldFiles];
    return YES;
}

- (void)pruneOldFiles {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:self.directory error:nil];
    if (!names.count) return;

    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *name in names) {
        if (![name.pathExtension isEqualToString:@"ndjson"]) continue;
        if (![name hasPrefix:self.baseName]) continue;
        [paths addObject:[self.directory stringByAppendingPathComponent:name]];
    }
    if (paths.count <= self.maxFiles) return;

    [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *attrsA = [manager attributesOfItemAtPath:a error:nil];
        NSDictionary *attrsB = [manager attributesOfItemAtPath:b error:nil];
        NSDate *dateA = attrsA[NSFileModificationDate] ?: [NSDate distantPast];
        NSDate *dateB = attrsB[NSFileModificationDate] ?: [NSDate distantPast];
        return [dateA compare:dateB];
    }];
    NSUInteger removeCount = paths.count - self.maxFiles;
    for (NSUInteger i = 0; i < removeCount; i++) {
        [manager removeItemAtPath:paths[i] error:nil];
    }
}

- (BOOL)appendData:(NSData *)data maxBytes:(unsigned long long)maxBytes {
    if (!data.length) return NO;
    if (!self.handle && ![self openNewFile]) return NO;
    if (self.size > 0 && self.size + data.length > maxBytes) {
        if (![self openNewFile]) return NO;
    }
    @try {
        [self.handle seekToEndOfFile];
        [self.handle writeData:data];
        self.size += data.length;
        self.recordCount++;
        return YES;
    } @catch (NSException *exception) {
        [self closeFile];
        return NO;
    }
}

@end

#pragma mark - 抓包管理

@interface AntManorCapture ()
@property (nonatomic, strong) ManorCaptureStream *mainStream;
@property (nonatomic, strong) ManorCaptureStream *familyStream;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *callbackOperations;
@property (nonatomic, assign) NSUInteger timedToken;
@property (nonatomic, assign) BOOL loggedSerializationFailure;
@end

@implementation AntManorCapture

@synthesize enabled = _enabled;

+ (instancetype)sharedInstance {
    static AntManorCapture *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AntManorCapture alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _callbackOperations = [NSMutableDictionary dictionary];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _enabled = [defaults objectForKey:kManorCaptureEnabledKey] ? [defaults boolForKey:kManorCaptureEnabledKey] : YES;

        NSString *directory = [self captureDirectory];
        _mainStream = [[ManorCaptureStream alloc] initWithDirectory:directory baseName:@"capture" timestamped:YES maxFiles:kManorCaptureMaxFiles];
        _familyStream = [[ManorCaptureStream alloc] initWithDirectory:directory baseName:@"family-candidates" timestamped:NO maxFiles:kManorCandidateMaxFiles];
    }
    return self;
}

- (NSString *)captureDirectory {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject ?: @"";
    NSString *directory = [documents stringByAppendingPathComponent:@"AntManor"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    // 抓包文件只留在本机，不进入 iCloud/iTunes 备份
    NSURL *directoryURL = [NSURL fileURLWithPath:directory isDirectory:YES];
    [directoryURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    return directory;
}

- (void)emitLog:(NSString *)message {
    if (!message.length) return;
    if (self.logHandler) {
        self.logHandler(message);
    } else {
        NSLog(@"[AntManorPort][capture] %@", message);
    }
}

- (void)setEnabled:(BOOL)enabled {
    BOOL changed = NO;
    @synchronized (self) {
        if (_enabled != enabled) {
            _enabled = enabled;
            changed = YES;
        }
    }
    if (!changed) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kManorCaptureEnabledKey];
    [defaults synchronize];
    if (enabled) {
        [self emitLog:[NSString stringWithFormat:@"抓包已开启，目录：%@", [self captureDirectory]]];
    } else {
        [self emitLog:@"抓包已关闭"];
    }
}

- (NSInteger)recordCount {
    @synchronized (self) {
        return self.mainStream.recordCount;
    }
}

- (NSInteger)familyCandidateCount {
    @synchronized (self) {
        return self.familyStream.recordCount;
    }
}

- (unsigned long long)currentFileSize {
    @synchronized (self) {
        return self.mainStream.size;
    }
}

- (NSString *)currentFilePath {
    @synchronized (self) {
        return self.mainStream.path ?: @"";
    }
}

- (NSString *)familyCandidatesPath {
    @synchronized (self) {
        return self.familyStream.path ?: @"";
    }
}

#pragma mark 写入

- (void)appendRecord:(NSDictionary *)record family:(BOOL)family {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:&error];
    if (!json.length) {
        if (!self.loggedSerializationFailure) {
            self.loggedSerializationFailure = YES;
            [self emitLog:[NSString stringWithFormat:@"抓包记录序列化失败：%@", error.localizedDescription ?: @"unknown"]];
        }
        return;
    }
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];

    @synchronized (self) {
        ManorCaptureStream *stream = family ? self.familyStream : self.mainStream;
        [stream appendData:line maxBytes:kManorCaptureMaxBytes];
    }
}

- (NSArray *)itemsFromMessage:(id)message {
    if (!message) return @[];
    if ([message isKindOfClass:NSArray.class]) return message;
    if ([message isKindOfClass:NSDictionary.class]) return @[message];
    if ([message isKindOfClass:NSString.class]) {
        NSString *text = message;
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([parsed isKindOfClass:NSArray.class]) return parsed;
        if ([parsed isKindOfClass:NSDictionary.class]) return @[parsed];
        return @[text];
    }
    return @[message];
}

- (void)recordRequestMessage:(id)message url:(id)url {
    if (!self.enabled || !message) return;

    NSString *timestamp = [ManorCaptureISODateFormatter() stringFromDate:[NSDate date]];
    NSString *urlString = ManorSanitizeURLString(url);
    NSArray *items = [self itemsFromMessage:message];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray arrayWithCapacity:items.count];

    for (id item in items) {
        NSString *operationType = ManorOperationType(item);
        if (!operationType.length) {
            NSString *raw = ManorCaptureText(item);
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\"operationType\"\\s*:\\s*\"([^\"]+)\"" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
            if (match.numberOfRanges > 1) operationType = [raw substringWithRange:[match rangeAtIndex:1]];
        }
        if (!operationType.length) operationType = @"unknown";

        NSString *callbackId = ManorFindStringValue(item, @"callbackId", 0);
        if (callbackId.length) {
            @synchronized (self) {
                if (self.callbackOperations.count > 500) [self.callbackOperations removeAllObjects];
                self.callbackOperations[callbackId] = operationType;
            }
        }

        NSDictionary *record = @{
            @"ts": timestamp ?: @"",
            @"direction": @"req",
            @"operationType": operationType,
            @"url": urlString ?: @"",
            @"payload": ManorSanitizeValue(item, 0, ManorSensitiveNone),
            @"responseSummary": @{},
        };
        [records addObject:record];
    }

    for (NSDictionary *record in records) {
        [self appendRecord:record family:NO];
    }
}

- (void)recordResponse:(id)response url:(id)url {
    if (!self.enabled || !response) return;

    id parsedResponse = response;
    if ([response isKindOfClass:NSString.class]) {
        NSData *data = [(NSString *)response dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (parsed) parsedResponse = parsed;
    }

    id sanitized = ManorSanitizeValue(parsedResponse, 0, ManorSensitiveNone);
    NSString *operationType = ManorOperationType(parsedResponse);
    NSString *responseId = ManorFindStringValue(parsedResponse, @"responseId", 0);
    if (!responseId.length) responseId = ManorFindStringValue(parsedResponse, @"callbackId", 0);
    if (!operationType.length && responseId.length) {
        @synchronized (self) {
            operationType = self.callbackOperations[responseId] ?: @"";
        }
    }
    if (!operationType.length) operationType = @"unknown";

    NSDictionary *summary = ManorResponseSummary(parsedResponse, sanitized);
    NSArray<NSString *> *matches = ManorFamilyMatches(sanitized, operationType);

    NSMutableDictionary *record = [@{
        @"ts": [ManorCaptureISODateFormatter() stringFromDate:[NSDate date]] ?: @"",
        @"direction": @"resp",
        @"operationType": operationType,
        @"url": ManorSanitizeURLString(url) ?: @"",
        @"payload": sanitized ?: [NSNull null],
        @"responseSummary": summary ?: @{},
    } mutableCopy];

    if (matches.count) {
        record[@"familyCandidate"] = @YES;
        record[@"matchedKeywords"] = matches;
    }
    [self appendRecord:record family:NO];

    if (matches.count) {
        NSMutableDictionary *candidate = [record mutableCopy];
        candidate[@"matchedKeywords"] = matches;
        [self appendRecord:candidate family:YES];
        [self emitLog:[NSString stringWithFormat:@"FAMILY_CANDIDATE op=%@ keywords=%@ path=%@",
                       operationType,
                       [matches componentsJoinedByString:@","],
                       self.familyCandidatesPath ?: @"(pending)"]];
    }
}

#pragma mark 定时抓包

- (void)startTimedCapture:(NSTimeInterval)duration completion:(void (^)(void))completion {
    NSTimeInterval interval = duration > 0 ? duration : 60.0;
    self.enabled = YES;

    NSUInteger token = 0;
    @synchronized (self) {
        self.timedToken += 1;
        token = self.timedToken;
    }

    [self emitLog:[NSString stringWithFormat:@"开始抓包 %.0f 秒：请现在去蚂蚁庄园「家庭」页面操作任务，结束后自动停止并可导出。", interval]];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AntManorCapture *strongSelf = weakSelf;
        if (!strongSelf) return;
        @synchronized (strongSelf) {
            if (token != strongSelf.timedToken) return;
        }
        if (strongSelf.enabled) strongSelf.enabled = NO;
        [strongSelf emitLog:[NSString stringWithFormat:@"定时抓包已结束，可导出：%@", [strongSelf exportPathDescription]]];
        if (completion) completion();
    });
}

#pragma mark 导出

- (NSArray<NSURL *> *)exportFileURLs {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    @synchronized (self) {
        [paths addObjectsFromArray:self.mainStream.sessionPaths];
        [paths addObjectsFromArray:self.familyStream.sessionPaths];
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([manager fileExistsAtPath:path]) {
            [urls addObject:[NSURL fileURLWithPath:path]];
        }
    }
    return urls;
}

- (NSString *)exportPathDescription {
    NSArray<NSString *> *paths = nil;
    @synchronized (self) {
        NSMutableArray<NSString *> *all = [NSMutableArray array];
        [all addObjectsFromArray:self.mainStream.sessionPaths];
        [all addObjectsFromArray:self.familyStream.sessionPaths];
        paths = [all copy];
    }
    NSMutableArray<NSString *> *existing = [NSMutableArray array];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([manager fileExistsAtPath:path]) [existing addObject:path];
    }
    if (!existing.count) return [self captureDirectory];
    if (existing.count == 1) return existing.firstObject;
    return [NSString stringWithFormat:@"%@ 等 %lu 个文件", existing.firstObject, (unsigned long)existing.count];
}

@end
