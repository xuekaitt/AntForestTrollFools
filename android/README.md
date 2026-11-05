# 蚂蚁庄园 · 家庭活动亲密度（Android / AccessibilityService 版）

纯界面自动化的 Android 版本：通过无障碍服务读取并点击支付宝「蚂蚁庄园 · 家庭」页面完成任务，
**不使用 root / Xposed / hook / 接口密钥**，应用本身不申请 `INTERNET` 权限，所有数据仅保存在本机。

> 构建验证状态：**已在本机实际执行 `:app:assembleDebug` 并产出 APK（2026-11-05，BUILD SUCCESSFUL）**。
> 当前产物：`dist/AntManorAndroid-v1.1.0-debug.apk`，943,701 字节，
> SHA-256 `8DFFB186CDB3BE80670BE1F31949393CB5E646FA7A58AE3DB7921739B3B2BE6C`，Android Debug 签名（可侧载，非发布签名）。
>
> 真机验证：Samsung SM-F741N（Android 17，1080×2640）。M1/M2 通过，M3 受当日任务可用性限制未通过。
> 详见 [TESTLOG.md](TESTLOG.md) 与 [TESTREPORT.md](TESTREPORT.md)。

## 关键实现（v1.1.0）

- **scheme 直达庄园**：`alipays://platformapi/startapp?appId=66666674`，参考 Ant-Manor（TonyJiangWJ）的做法，
  绕开支付宝首页 canvas 入口无法被节点识别的问题；manifest 已声明 `alipays` 的 `<queries>`（Android 11+ 包可见性）。
- **家庭入口按比例点击**：footer 第三个图标（0.405 / 0.903），点击后等待并校验「相亲相爱一家人」标题。
- **两层弹窗处理**：文字「跳过/关闭」优先，其次用「水平居中 + 接近正方形 + 下半屏」的关闭按钮启发式。
- **亲密度抽屉**：点击「立即签到」展开后，任务卡片文字可读；按 `family:<task>` 去重，风控文案立即停止。
- **安全跳过**：外卖/红包/淘宝、捐蛋/爱心蛋/捐步、支付/授权/开通等关键词一律不点击。
- **整屏坐标**：`WindowManager.maximumWindowMetrics` 取物理屏幕尺寸，避免服务 `displayMetrics` 不含导航栏导致底部点击偏移。

## 构建前提

- JDK 17
- Android SDK：`platforms;android-34`、`build-tools;34.0.0`
- Android Studio（推荐 Ladybug 或更新版本），或仅用命令行工具

## 本机实际可用的构建方式（已跑通）

本仓库使用「工作区内便携工具链」，不安装系统级软件、不需要管理员权限：

```powershell
# 1) 工具链位置（下载解压即可，已在 .toolchain 内）
#    JDK 17      : .toolchain\jdk\jdk-17.0.21+9
#    Android SDK : .toolchain\sdk （内含 cmdline-tools\latest、platforms\android-34、build-tools\34.0.0）

# 2) 环境变量（当前 PowerShell 会话）
$env:JAVA_HOME      = "d:\桌面\AntForestTrollFools\.toolchain\jdk\jdk-17.0.21+9"
$env:ANDROID_HOME   = "d:\桌面\AntForestTrollFools\.toolchain\sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

# 3) 构建（工程自带 Gradle 8.7 wrapper）
& "d:\桌面\AntForestTrollFools\android\gradlew.bat" -p "d:\桌面\AntForestTrollFools\android" :app:assembleDebug

# 4) 产物
#    android\app\build\outputs\apk\debug\app-debug.apk
#    复制到 dist\ 并改名为 AntManorAndroid-v1.1.0-debug.apk
```

构建相关的两个必需设置：

| 设置 | 原因 |
| --- | --- |
| `gradle.properties` 中 `android.overridePathCheck=true` | 工程路径含中文（`d:\桌面\...`），AGP 默认会因非 ASCII 路径直接报 `StopExecutionException` |
| `local.properties` 中 `sdk.dir` 使用 `\u684C\u9762` 转义 | Java properties 按 ISO-8859-1 读取，中文路径必须写成 Unicode 转义；也可不写该文件，直接依赖 `ANDROID_HOME` |


## 在 Android Studio 中构建

1. `File → Open`，选择本目录 `android/`（不是仓库根目录）。
2. 首次同步时 Studio 会按 `gradle/wrapper/gradle-wrapper.properties` 下载 Gradle 8.7；
   若 wrapper 下载被阻断，可在 `Settings → Build Tools → Gradle` 选择「本地 Gradle」并指向已安装的 8.7+。
3. 等待 SDK 34 组件下载完成。
4. 连接真机（Android 8.0 / API 26 及以上），点击 Run，或执行：

```bash
# Windows
gradlew.bat :app:assembleDebug
# macOS / Linux
./gradlew :app:assembleDebug
```

产物：`app/build/outputs/apk/debug/app-debug.apk`

> 说明：本工程只依赖 Android Framework API，`dependencies {}` 为空，便于离线构建与安全审查。

## 首次使用

1. 安装后打开应用，弹窗会引导你完成 3 件事（应用不会自动开启无障碍）：
   - 系统设置 → 无障碍 → 已下载的服务 → 「庄园亲密度自动化」→ 开启；
   - 允许通知；
   - 加入电池优化白名单（应用内按钮直达）。
2. 返回主页打开「总开关」，再点「开始运行」。
3. 若系统限制后台启动支付宝，请到「参数设置」关闭「自动从支付宝首页进入」，并手动打开支付宝进入家庭页。

## 权限与安全边界

| 项目 | 说明 |
| --- | --- |
| 网络权限 | 完全不声明 `INTERNET`，从系统层面杜绝上传 |
| 无障碍范围 | 服务配置仅监听 `com.eg.android.AlipayGphone`，其余应用界面不会被读取 |
| 风控 | 命中验证码/滑块/安全验证等关键词立即停止，不做任何绕过 |
| 节流 | 最小操作间隔可配置，并在其基础上叠加最多约 1/3 的随机抖动，避免固定节奏；两次操作之间不会抢跑 |
| 支付类任务 | 文案含「支付/捐赠/充值/购买/授权/签约」等关键词的任务直接跳过 |
| 日志 | 只写本机私有目录 `files/manor-log.txt`，条数上限可配置（默认 300） |
| 开关 | 总开关默认关闭；每次扫描都会重新读取总开关，随时可停 |

## 页面适配（选择器外置）

支付宝是 H5/混合页面，节点文案会随版本变化。应用支持不改代码校准：

1. 主页点「导出当前界面节点快照（校准用）」，文件位于
   `Android/data/com.antmanor.automation/files/snapshots/snapshot-*.txt`
   （字段：深度 / class / viewId / clickable / text / contentDescription / bounds）。
2. 如需固定 resource-id 或改写关键词，把 `manor-selectors.json` 放到应用外部私有目录：
   `Android/data/com.antmanor.automation/files/manor-selectors.json`
   （也可放内部 `files/` 目录；外部目录无需 root 即可通过文件管理器或 `adb push` 写入），格式示例：

```json
{
  "manorEntryIds": ["com.eg.android.AlipayGphone:id/xxx"],
  "manorEntryTexts": ["蚂蚁庄园"],
  "familyEntryTexts": ["家庭", "家庭任务"],
  "taskTodoActions": ["去完成", "去逛逛"],
  "taskClaimActions": ["领取", "开心收下"],
  "skipKeywords": ["支付", "捐赠", "充值"],
  "riskKeywords": ["滑块", "验证码", "安全验证"]
}
```

字段可省略；解析失败会自动回退默认值并记录日志。查找顺序固定为
**resource-id → text → contentDescription**。

## 真机验证清单

- [ ] 无障碍服务可手动开启，主页显示「已连接」
- [ ] 总开关默认关闭，关闭时不会自动开始
- [ ] 自动拉起支付宝 / 手动进入家庭页两种方式都能进入流程
- [ ] 首页能识别「蚂蚁庄园」入口并点击进入
- [ ] 庄园页能识别「家庭」入口并点击进入
- [ ] 家庭页任务卡片能被扫描到（标题、按钮文案）
- [ ] 领取类任务点击后出现奖励弹窗并能关闭
- [ ] 任务页停留后返回，任务数 +1，日志有记录
- [ ] 达到每日任务上限 / 亲密度上限时自动停止
- [ ] 最小操作间隔生效（连续点击不会过快）
- [ ] 遇到验证码/滑块页面立即停止且积分页无任何后续操作
- [ ] 「今日亲密度」「任务数」「活动剩余时间」显示正确
- [ ] 排名读得到时显示第 N 名及前 200 万判断；读不到显示「未获取」
- [ ] 前台常驻通知随状态更新，停止后消失
- [ ] 通知权限被拒绝时应用仍可运行（有降级提示）
- [ ] 关闭总开关后运行中的任务在下一次扫描内停止

## 已知限制

- 任务列表若需要滚动才能看到更多卡片，当前版本不会自动滚动（避免误触）。
- 排名依赖页面文案，若活动页不显示排名则一直为「未获取」。
- 支付宝版本升级后可能需要重新导出快照并校准选择器；校准失败时应保持「失败即停」。
- Android 12 及以上若限制后台启动前台服务，状态通知会降级为普通通知（运行逻辑不受影响）。
