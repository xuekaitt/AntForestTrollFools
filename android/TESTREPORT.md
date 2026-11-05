# 真机测试报告（v1.1.0）

日期：2026-11-05
设备：Samsung SM-F741N（Galaxy Z Flip6）
系统：Android 17 / API 37
屏幕：1080×2640，480dpi
应用：`com.antmanor.automation`，versionCode 4，versionName 1.1.0

## 测试结论

| 里程碑 | 结果 | 说明 |
| --- | --- | --- |
| M1 可安装、可打开、无障碍连接 | 通过 | `adb install` 成功；无障碍服务绑定；主界面显示状态 |
| M2 自动进入庄园家庭页并识别任务 | 通过 | scheme 直达庄园 → 家庭入口 → 签到 → 任务抽屉；任务标题与按钮可读 |
| M3 完成一个任务并记录亲密度 | 未通过 | 当天签到已手工完成；其余任务时间未到/缺少小鸡/需捐步，捐赠与外卖任务被安全策略跳过 |
| 风控与安全边界 | 通过 | 未声明 INTERNET；未注入脚本；不进入支付/授权/捐赠流程；遇风控文案立即停止 |

## 最终产物

- 路径：`dist/AntManorAndroid-v1.1.0-debug.apk`
- 体积：943,701 字节（约 922 KB）
- SHA-256：`8DFFB186CDB3BE80670BE1F31949393CB5E646FA7A58AE3DB7921739B3B2BE6C`
- 签名：Android Debug（`C=US, O=Android, CN=Android Debug`）

## 已验证行为

1. 用 `alipays://platformapi/startapp?appId=66666674` 直接进入蚂蚁庄园，不再依赖首页入口。
2. 首次进入主场景等待 H5 加载，家庭入口按 0.405/0.903 点击，8 秒内进入「相亲相爱一家人」。
3. 自动关闭「跳过」推广弹层与中心 X 奖励弹层。
4. 点击「立即签到」打开亲密度任务抽屉，识别出 5 个任务卡片。
5. 安全模式只完成签到，不进入任务详情；本次退出时回到庄园主场景，无残留弹窗。
6. 读取「活动期间亲密度 8」并写入本地状态。

## 未通过项与原因

- 自动完成一个任务并记录 `todayTasks`：当天「立即签到」已手工完成，未产生新的亲密度增量，因此未计入；其余任务：
  - 请家人吃饭：18:00 后才可请客（当前 04:00）；
  - 帮喂小鸡：暂无小鸡可喂；
  - 一起运动：不满足捐步条件；
  - 每日捐蛋：进入公益捐赠项目页，属于捐赠类，按安全边界跳过；
  - 外卖红包：跳转淘宝「访问被拒绝」页，按外部/广告类跳过。

## 已知限制

- 家庭小屋、签到按钮是 canvas，只能按屏幕比例点击；默认比例基于 1080×2640 标定，其它宽高比需要重新校准 `SceneHotspots` 与 `FAMILY_SIGNIN_X/Y`。
- 支付宝 H5 文案与任务规则会随版本变化；选择器可通过 `manor-selectors.json` 外置覆盖。
- 后台从服务侧启动 Activity 在 Android 10+ 可能被限制；正常路径由主界面（前台）发起 scheme，服务侧仅兜底。
- Android 12+ 前台服务特殊用途限制可能导致常驻通知降级为普通通知。

## 复现步骤

```powershell
adb install -r dist\AntManorAndroid-v1.1.0-debug.apk
adb shell pm grant com.antmanor.automation android.permission.POST_NOTIFICATIONS
adb shell settings put secure enabled_accessibility_services com.antmanor.automation/com.antmanor.automation.ManorAccessibilityService
adb shell settings put secure accessibility_enabled 1
adb shell am start -a android.intent.action.VIEW -d "alipays://platformapi/startapp?appId=66666674" -p com.eg.android.AlipayGphone
# 打开应用 → 总开关开启（会自动开始）
# 日志：adb shell run-as com.antmanor.automation cat files/manor-log.txt
```
