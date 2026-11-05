# AntManorPort（蚂蚁庄园 · 家庭亲密度）

基于 TrollStore + TrollFools 的支付宝 H5 注入插件，**只保留蚂蚁庄园**（每日签到、小课堂答题、投喂、收取肥料、领取饲料任务奖励），并在其上增加「家庭活动期亲密度」能力。蚂蚁森林、芭芭农场、神奇海洋、AI 摸鱼、保护地等模块已全部移除。

- 语言：Objective-C（ARC，Objective-C Runtime Hook）
- 产物：`arm64 + arm64e` 通用 dylib，iOS 14 及以上
- 不依赖 MobileSubstrate / Theos / CaptainHook

> 仅用于个人学习与自动化研究。请自行评估账号风险并遵守支付宝/蚂蚁庄园的活动规则。本项目不提供绕过风控或安全机制的能力。

## 构建

需要 macOS + Xcode Command Line Tools（Windows 无法编译 iOS dylib）。

```sh
make                 # 生成 build/AntManorPort-v3.6.0.dylib（arm64 + arm64e）
make test            # 裁剪/残留静态自检
make package         # 生成 dist/*.deb 与 TrollFools 可用 zip
```

`make` 使用 `xcrun --sdk iphoneos` 的 SDK/Clang，并把两个架构 `lipo` 合并为一个通用 dylib。

## CI（GitHub Actions）

前提：先把仓库推送到 GitHub，并确认 **Settings → Actions → General** 允许运行 Actions（新建仓库默认启用；Fork 仓库需手动开启）。

工作流文件：[.github/workflows/ios-build.yml](.github/workflows/ios-build.yml)

| 触发方式 | 行为 |
| --- | --- |
| push 到 `main` / `master` | 构建 + 自检 + 打包，上传 artifact |
| pull_request | 同上（fork PR 默认只读，不会发 Release） |
| `workflow_dispatch` | 在 Actions 页面手动运行 |
| push tag `v*` | 同上，并创建 GitHub Release 附加产物 |

- Runner：`macos-latest`，优先 `maxim-lobanov/setup-xcode` 选择 Xcode `15.4`；若镜像已移除该版本，自动回退到默认 Xcode。
- 产物（Actions Run 页面 Artifacts，保留 30 天）：
  - `AntManorPort-v3.6.0-build<run_number>-dylib`：`build/*.dylib`
  - `AntManorPort-v3.6.0-build<run_number>-packages`：`dist/*.deb`、`dist/*-TrollFools.zip`
- `make package` 失败不会中断构建，至少保留 dylib 产物（日志会有 warning）。
- Tag Release 使用 `softprops/action-gh-release`，依赖 workflow 中的 `permissions: contents: write`；建议 tag 与 Makefile 的 `VERSION` 保持一致（如 `v3.6.0`），否则 Release 名称与包内版本可能不同。
- deb 打包优先使用 Homebrew 的 `dpkg-deb`；不可用时 `scripts/package.sh` 自动回退到 `ar + tar`。
- CI 只做构建与打包，不需要任何账号 cookie/token；仓库中也没有敏感配置。

本地等价命令：

```sh
make          # 等同于 CI 的 Build dylib
make test     # 等同于 CI 的 Static self-check
make package  # 等同于 CI 的 Package（需先 make）
```

## 安装

1. 用 TrollFools 注入支付宝（Bundle ID：`com.alipay.iphoneclient`），选择 `dist/com.vknote.antmanor_3.6.0_iphoneos-arm.deb` 或 `AntManorPort-v3.6.0-TrollFools.zip`；
2. 打开蚂蚁庄园页面，右侧会出现叶子悬浮按钮；
3. 点击按钮打开「蚂蚁庄园 · 家庭亲密度」面板。

## 家庭亲密度配置

插件只硬编码了项目原有、已验证的庄园接口。**未抓包确认的家庭任务/排名接口不会主动请求**，必须通过本地配置注入：

把 [config/manor-config.example.json](config/manor-config.example.json) 复制到支付宝沙盒：

```
Documents/AntManor/manor-config.json
```

然后按抓包结果填写以下字段（留空即禁用）：

| 字段 | 说明 |
| --- | --- |
| `activityEnabled` | 是否启用家庭亲密度自动化（默认关闭，可在面板开关或配置中开启） |
| `activityStartDate` / `activityEndDate` | 活动期 `yyyy-MM-dd`，留空表示不限制 |
| `dailyTaskLimit` | 每日最多执行任务数（默认 10） |
| `dailyIntimacyCap` | 每日可得亲密度上限；`0` 表示未配置，仅展示 |
| `minRequestInterval` | 两次任务请求最小间隔秒数（默认 45） |
| `topNThreshold` | 奖励线，默认 2000000 |
| `familyTaskOperationType` | 家庭任务执行 RPC 名（待抓包） |
| `familyTaskRequestData` | 家庭任务请求体 JSON 数组，支持 `{{bizKey}}` `{{taskId}}` `{{activityId}}` `{{taskType}}` |
| `familyTaskClaimOperationType` | 家庭任务领奖 RPC 名（待抓包） |
| `familyTaskClaimRequestData` | 领奖请求体 JSON 数组，可留空 |
| `rankOperationType` | 亲密度排名 RPC 名（待抓包） |
| `rankRequestData` | 排名请求体 JSON 数组，可留空 |

也可用 `NSUserDefaults` 覆盖，键名为 `manor_cfg_<字段名>`。

## 调试抓包（仅本地）

家庭任务接口需要真实抓包确认。v3.4.0 内置了本地抓包模块，v3.5.0 补充了 `_dispatchMessage:` 请求侧 Hook；v3.6.0 用第二份抓包复核后仍未捕获家庭任务请求，因此配置继续保持为空：

1. 打开蚂蚁庄园「家庭」页面，点击悬浮叶子进入面板；
2. 面板 →「调试抓包」开关默认开启；也可点「开始抓包 60 秒」，按提示立即去操作家庭任务；
3. 60 秒后自动停止；点击「导出抓包文件」通过系统分享面板导出；
4. 把导出的 **`capture-YYYYMMDD-HHMMSS.ndjson`** 和（如果有）**`family-candidates.ndjson`** 发给开发者分析。

文件位置：`Documents/AntManor/`（面板「复制抓包路径」可直接复制路径）。

- **记录范围**：所有经 `PSDJsBridge _doFlushMessageQueue:url:` / `_dispatchMessage:` 发出的请求，以及 `transformResponseData:` 收到的回包，包含 H5 页面自身发出的 RPC；同一 `callbackId` 自动去重。
- **格式**：NDJSON，每行一个 JSON，字段为 `ts`、`direction`（req/resp）、`operationType`、`url`、`payload`、`responseSummary`；`responseSummary` 包含顶层 key、`resData`/`data`/`result` 包装层、包装层 key 与关键字段值。
- **容量**：单文件上限 5MB，超过自动滚动到新的时间戳文件；主日志最多保留 10 个文件，候选日志最多 5 个。
- **FAMILY_CANDIDATE**：回包内容命中 `family`、`intimacy`、`亲密度`、`homeTask`、`activity` 时，面板日志会打印醒目的 `FAMILY_CANDIDATE` 标记，并额外写入 `family-candidates.ndjson`，方便只发这一个文件。
- **脱敏**：以下字段的值会被掩码或替换，但保留字段名与结构：token、cookie、session 及各类 auth/ticket/secret/signature；手机号；身份证号；银行卡/银行账号；userId/uid/openid/memberId 等用户标识；email；真实姓名；地址。URL 查询参数中的敏感键同样替换为 `***`。单条字符串超过 500 字符会截断并标注长度。
- **隐私**：抓包只写入 App 沙盒本地文件，不联网、不上传；请勿把包含账号信息的原始文件公开发布。

## 能力说明

- **庄园自动化**：每日签到、小课堂答题、防重复投喂、收取肥料、浏览类任务与领奖；跳过公益捐款、游戏充值、支付类任务。
- **亲密度任务节流**：按任务来源（庄园/家庭）、任务 ID、每日任务数、每日亲密度上限、请求间隔、每日请求数上限去重与节流；同一任务不会重复提交。
- **进度记录**：今日新增亲密度、完成任务数、请求次数、每日上限、活动期状态，均持久化到 `NSUserDefaults` 并在面板展示。
- **排名**：抓包确认家庭页会下发 `activityInfo.familyActivityIntimateRankList` 排名线（如前 50 名需 592 亲密度），面板会展示该阈值；个人名次/总人数仍需要单独的排名接口，未配置时不会主动请求。
- **家庭页观测**：解析 `familyActivityIntimateNumber`、`familyDailyIntimateNumber`、`familyIntimateAwardGear`、`activityInfo` 与 `familyTasks`，在面板展示活动亲密度、家庭总亲密度、活动期、排名线和家庭任务概览。
- **请求通道**：复用原项目的 `PSDJsBridge _doFlushMessageQueue:url:` + `operationType` 机制，签名/登录态仍由支付宝 H5 容器负责。

## 抓包分析结论与缺口

详见 [docs/capture-analysis.md](docs/capture-analysis.md)。

- **已确认回包结构**：家庭页 `familyTasks`（`sceneCode=ANTFARM_FAMILY_TASK`）、`familyActivityIntimateNumber`、`familyDailyIntimateNumber`、`familyIntimateAwardGear`、`activityInfo.familyActivityIntimateRankList`。
- **已确认的庄园任务接口**：`listFarmTask`、`doFarmTask`、`receiveFarmTaskAward`，请求/回包字段已与抓包对齐。
- **仍未抓到请求侧**：家庭任务列表/执行/领奖的 `operationType`。两次抓包（v3.4.0 与 v3.5.0）中家庭页只出现回包（`familyTasks`、`familyActivityIntimateNumber` 等），请求侧一条都没有；`_dispatchMessage:` Hook 也未命中，说明家庭页 RPC 不走该实例方法。面板可解析并展示家庭任务状态与 `taskId` 动作，但不会发出请求。
- **下一步建议**：优先用 Thor/mitmproxy 做 HTTPS 层抓包（可能遇到证书固定），或改用安卓无障碍版本点击真实按钮；继续加 iOS Hook（`+dispatchJsapiInFastMode:targetNode:responseCallback:` 等）需要真机验证，v3.6.0 暂未采用。
- **个人排名接口**：抓包只有排名线（分档阈值），没有名次与总人数接口；未抓到时不发请求。
- **每日亲密度上限**：抓包未出现明确上限字段，保持 `0`（仅展示，不限制）。

## 目录结构

```
PortEntry.m                     注入入口、悬浮按钮、面板、H5/RPC Hook
antforest/AntManorManager.{h,m} 庄园桥接、日常自动化、回包处理
antforest/AntManorIntimacy.{h,m} 家庭亲密度配置、任务节流、进度、排名
antforest/AntManorCapture.{h,m}  本地 RPC 抓包、脱敏、NDJSON、FAMILY_CANDIDATE
antforest/Headers/PSDJsBridge   仅保留注入所需的 Bridge 头文件
antforest/Package                deb 打包骨架
config/                         亲密度配置模板（不含任何账号信息）
scripts/package.sh              deb/zip 打包脚本
tests/check_manor_only_paths.sh 裁剪残留自检
```
