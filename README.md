# AntManorPort（蚂蚁庄园 · 家庭亲密度）

基于 TrollStore + TrollFools 的支付宝 H5 注入插件，**只保留蚂蚁庄园**（每日签到、小课堂答题、投喂、收取肥料、领取饲料任务奖励），并在其上增加「家庭活动期亲密度」能力。蚂蚁森林、芭芭农场、神奇海洋、AI 摸鱼、保护地等模块已全部移除。

- 语言：Objective-C（ARC，Objective-C Runtime Hook）
- 产物：`arm64 + arm64e` 通用 dylib，iOS 14 及以上
- 不依赖 MobileSubstrate / Theos / CaptainHook

> 仅用于个人学习与自动化研究。请自行评估账号风险并遵守支付宝/蚂蚁庄园的活动规则。本项目不提供绕过风控或安全机制的能力。

## 构建

需要 macOS + Xcode Command Line Tools（Windows 无法编译 iOS dylib）。

```sh
make                 # 生成 build/AntManorPort-v3.3.0.dylib（arm64 + arm64e）
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
  - `AntManorPort-v3.3.0-build<run_number>-dylib`：`build/*.dylib`
  - `AntManorPort-v3.3.0-build<run_number>-packages`：`dist/*.deb`、`dist/*-TrollFools.zip`
- `make package` 失败不会中断构建，至少保留 dylib 产物（日志会有 warning）。
- Tag Release 使用 `softprops/action-gh-release`，依赖 workflow 中的 `permissions: contents: write`；建议 tag 与 Makefile 的 `VERSION` 保持一致（如 `v3.3.0`），否则 Release 名称与包内版本可能不同。
- deb 打包优先使用 Homebrew 的 `dpkg-deb`；不可用时 `scripts/package.sh` 自动回退到 `ar + tar`。
- CI 只做构建与打包，不需要任何账号 cookie/token；仓库中也没有敏感配置。

本地等价命令：

```sh
make          # 等同于 CI 的 Build dylib
make test     # 等同于 CI 的 Static self-check
make package  # 等同于 CI 的 Package（需先 make）
```

## 安装

1. 用 TrollFools 注入支付宝（Bundle ID：`com.alipay.iphoneclient`），选择 `dist/com.vknote.antmanor_3.3.0_iphoneos-arm.deb` 或 `AntManorPort-v3.3.0-TrollFools.zip`；
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

## 能力说明

- **庄园自动化**：每日签到、小课堂答题、防重复投喂、收取肥料、浏览类任务与领奖；跳过公益捐款、游戏充值、支付类任务。
- **亲密度任务节流**：按任务来源（庄园/家庭）、任务 ID、每日任务数、每日亲密度上限、请求间隔、每日请求数上限去重与节流；同一任务不会重复提交。
- **进度记录**：今日新增亲密度、完成任务数、请求次数、每日上限、活动期状态，均持久化到 `NSUserDefaults` 并在面板展示。
- **排名**：接口配置后才可查询；从回包中识别 `familyRankInfo` / `intimacyRankInfo` / `rankInfo` 等结构，展示名次与是否处于前 200 万名。未配置时面板明确提示「需抓包」。
- **请求通道**：复用原项目的 `PSDJsBridge _doFlushMessageQueue:url:` + `operationType` 机制，签名/登录态仍由支付宝 H5 容器负责。

## 仍需抓包确认

1. 家庭活动任务列表接口：当前只能从庄园页面回包里尝试识别 `familyTaskList` / `familyActivityTaskList` / `activityTaskList` / `intimacyTaskList` / `homeTaskList`；
2. 家庭任务的执行（do）与领奖（claim）RPC 名及请求体字段；
3. 亲密度排名接口、名次/总人数/奖励资格的字段路径；
4. 每日亲密度实际上限与活动起止时间（用于校正配置）。

## 目录结构

```
PortEntry.m                     注入入口、悬浮按钮、面板、H5/RPC Hook
antforest/AntManorManager.{h,m} 庄园桥接、日常自动化、回包处理
antforest/AntManorIntimacy.{h,m} 家庭亲密度配置、任务节流、进度、排名
antforest/Headers/PSDJsBridge   仅保留注入所需的 Bridge 头文件
antforest/Package                deb 打包骨架
config/                         亲密度配置模板（不含任何账号信息）
scripts/package.sh              deb/zip 打包脚本
tests/check_manor_only_paths.sh 裁剪残留自检
```
