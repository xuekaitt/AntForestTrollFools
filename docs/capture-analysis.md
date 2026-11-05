# 抓包分析：蚂蚁庄园 / 家庭页（2026-11-05）

分析对象：`capture-20261105-143022.ndjson`（414 条记录，约 584 KB，14:30:22—14:30:59）。
抓包范围：支付宝 iOS 端，蚂蚁庄园首页 + 家庭页 `familyFeed.html`（页面 ID `180020380000000271`）。

> 结论优先：本次抓包**补齐了庄园任务接口与家庭页回包结构**，但**没有抓到家庭任务执行/领奖的请求侧 operationType**。因此相关配置仍保持为空，不用猜测值填充。
>
> 后续在 v3.5.0 上又抓了一份 `capture-20261105-150221.ndjson` 复核，结论不变（详见第 9 节）：家庭任务请求仍未被本地 Hook 捕获，`familyTaskOperationType` / `familyTaskClaimOperationType` 继续保持为空。

## 1. 记录总览

| 指标 | 数值 |
| --- | --- |
| 总记录 | 414 |
| 请求（direction=req） | 40 |
| 回包（direction=resp） | 374 |
| 可识别 operationType | 6 个 |
| operationType=unknown 的请求 | 23（paladin 小游戏容器消息，非庄园 RPC） |
| operationType=unknown 的回包 | 370（回包没有 `responseId`，无法直接配对） |

## 2. operationType 聚合表

| operationType | req | resp | 页面 | 语义 | 是否改变状态 |
| --- | --- | --- | --- | --- | --- |
| `com.alipay.antfarm.listFarmTask` | 1 | 回包被记成 unknown | 庄园首页 | 庄园任务列表读取 | 否（只读） |
| `com.alipay.antfarm.doFarmTask` | 2 | 回包被记成 unknown | 庄园首页 | 任务上报/执行（签到等） | 是 |
| `com.alipay.antfarm.receiveFarmTaskAward` | 7 | 回包被记成 unknown | 庄园首页 | 任务领奖 | 是 |
| `com.alipay.antfarm.feedAnimal` | 1 | 回包被记成 unknown | 家庭页（插件主动发） | 投喂小鸡 | 是 |
| `com.alipay.gameevent.biz.rpc.submitEvent` | 6 | 回包被记成 unknown | paladin 小游戏 | 小游戏埋点（GetAuthCode 等） | 仅统计 |
| `com.alipay.promofrontcenter.deliver.deliverByPageId` | — | 4 | 家庭页/庄园 | 页面数据直投（prefetch），含 `result.componentList` | 否（只读） |

说明：回包端没有 `responseId`/`responseType`，抓包模块只能按时间和顺序推断配对；本次已把 `ariverRpcTraceId` 加入 `responseSummary.highlights`，便于下一版对齐。

## 3. 请求体（已脱敏，字段名保持原样）

### 3.1 任务列表 `listFarmTask`

```json
[
  {
    "version": "1.8.2302070202.46",
    "requestType": "NORMAL",
    "source": "H5",
    "sceneCode": "ANTFARM"
  }
]
```

### 3.2 任务上报 `doFarmTask`

```json
[
  {
    "bizKey": "JINDOU_QD260702",
    "requestType": "NORMAL",
    "sceneCode": "ANTFARM",
    "source": "H5",
    "version": "1.8.2302070202.46"
  }
]
```

### 3.3 任务领奖 `receiveFarmTaskAward`

```json
[
  {
    "requestType": "NORMAL",
    "sceneCode": "ANTFARM",
    "source": "H5",
    "taskId": "ANSWER",
    "version": "1.8.2302070202.46"
  }
]
```

### 3.4 投喂 `feedAnimal`

```json
[
  {
    "farmId": "",
    "animalType": "CHICK",
    "source": "H5",
    "sceneCode": "ANTFARM",
    "canMock": true,
    "version": "1.8.2302070202.46",
    "requestType": "NORMAL"
  }
]
```

## 4. 回包结构（真实抓包）

### 4.1 任务列表回包（对应 `listFarmTask`）

顶层：`signList`、`farmTaskList`、`memo`、`success`、`resultCode`、`ariverRpcTraceId`。

`farmTaskList[]` 关键字段：

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| `taskId` / `bizKey` | `ANSWER` / `JINDOU_QD260702` | 任务唯一 ID；提交通常用 `bizKey`，领奖用 `taskId` |
| `taskStatus` | `TODO` / `FINISHED` / `RECEIVED` | 待完成 / 待领奖 / 已领奖 |
| `title` / `taskDesc` / `desc` | `庄园小课堂` | 任务文案 |
| `awardType` | `ALLPURPOSE` / `FAMILY_INTIMACY` | 奖励类型 |
| `awardCount` | `90` | 奖励数量；`FAMILY_INTIMACY` 时表示亲密度 |
| `rightsTimes` / `rightsTimesLimit` | `0` / `1` | 已完成次数 / 次数上限 |
| `canReceiveAwardCount` | `90` | 可领数量 |
| `taskRightType` | `FIXED_AWARD_COUNT` | 奖励计算方式 |
| `taskPlayType` / `taskMode` | `OTHER` / `COUNT_DOWN` | 任务类型/倒计时 |
| `targetUrl` | `alipays://platformapi/startapp?...` | 跳转地址（不做自动化） |
| `deliveryControlItem.iepTaskTracer` | `sceneCode:ANTFARM_FOOD_TASK...` | 任务追踪串 |

### 4.2 家庭页状态回包（顶层直投，无 operationType）

顶层关键字段：

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| `success` / `resultCode` | `true` / `100` | 成功标记 |
| `familyActivityIntimateNumber` | `25` | 家庭活动亲密度 |
| `familyDailyIntimateNumber` | `4828` | 家庭总亲密度（今日/累计口径由服务端定义） |
| `familyIntimateAwardGear` | `50` | 当前奖励档位阈值 |
| `familyAwardNum` | `0` | 已领家庭奖励数 |
| `groupId` / `groupName` | `-` / `-` | 家庭 ID / 名称（抓包中为空或掩码） |
| `familyMemberInfoList[]` | — | 家庭成员列表 |
| `activityInfo.activityId` | `261022` | 活动 ID |
| `activityInfo.activityStartTime` | `1792810800000` | 活动开始（毫秒）→ 2026-10-24 |
| `activityInfo.activityEndTime` | `1796313599000` | 活动结束（毫秒）→ 2026-12-03 |
| `activityInfo.familyActivityIntimateRankList[]` | 见下 | 排名线（分档阈值，不是个人名次） |

`familyActivityIntimateRankList[]`：

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| `familyActivityRankIntimateGear` | `50` | 名次档位（前 50 名） |
| `familyActivityRankIntimateGearScore` | `592` | 进入该档位所需亲密度 |

抓包实测：前 50 名 592 / 前 100 名 358 / 前 200 名 215。

### 4.3 家庭任务列表回包（顶层 `familyTasks`，单独一次下发）

```json
{
  "success": true,
  "familyTasks": [
    {
      "bizKey": "TREAT",
      "taskId": "TREAT",
      "title": "请家人吃一顿美食",
      "desc": "在就餐时间请家人吃美食",
      "innerAction": "EAT_TOGETHER",
      "btnText": "去请客",
      "taskStatus": "TODO",
      "awardType": "FAMILY_INTIMACY",
      "awardCount": 3,
      "rightsTimes": 1,
      "rightsTimesLimit": 3,
      "alreadyReceiveStageAwardCount": 3,
      "canReceiveAwardCount": 3,
      "taskRightType": "FIXED_AWARD_COUNT",
      "taskEntityExpireTime": 1793894400000,
      "extend": "{\"canDo\":\"false\"}"
    }
  ]
}
```

抓包中出现的家庭任务（`sceneCode=ANTFARM_FAMILY_TASK`，两次下发内容一致）：

| taskId | taskStatus | innerAction | canDo | awardCount | 语义 |
| --- | --- | --- | --- | --- | --- |
| `TREAT` | TODO | `EAT_TOGETHER` | false | 3 | 请家人吃饭（非就餐时间不可做） |
| `HELP_FEED_PRIZE` | TODO | — | false | 0 | 帮家人喂鸡领奖 |
| `DAILY_DONATE` | RECEIVED | `DONATION` | — | 10 | 每日捐蛋 |
| `FAMILY_TREAD_MALL` | RECEIVED | — | — | 2 | 家庭逛逛（商城） |
| `FAMILY_SHANGOU` | RECEIVED | — | — | 1 | 家庭闪购 |

字段说明：

- `taskId` / `bizKey` 是家庭任务的动作标识（如 `TREAT`）。
- `taskStatus` 为 `TODO` / `RECEIVED`；本次没有看到 `FINISHED` / `WAIT_RECEIVE` 的家庭任务。
- `extend` 是 JSON 字符串；`canDo=false` 表示当前时间不可执行（例如吃饭任务只在就餐时间可做）。
- `awardType=FAMILY_INTIMACY` 时，`awardCount` 就是亲密度值。
- `innerAction` 是任务内部动作（`EAT_TOGETHER`、`DONATION` 等），可用于后续推断执行接口，但本次未抓到对应请求。

## 5. 配对与推断

- `listFarmTask` 的请求在 14:30:27.98，回包在 14:30:28.40（`farmTaskList`），间隔 0.42s。
- `receiveFarmTaskAward` 连续 7 次，对应插件对 `ANSWER` 等已完成的庄园任务领奖。
- `doFarmTask` 2 次，其中 `JINDOU_QD260702` 对应金豆夺宝签到。
- `feedAnimal` 1 次，由插件主动发起（callbackId 前缀 `rpc_manor_feed_`）。
- 家庭页的 `familyTasks` 回包在 14:30:44.256 和 14:30:51.072 两次到达，但**前后没有任何请求记录**（家庭页在本次抓包中只产生了插件自己的 `feedAnimal`）。推断：家庭页数据由容器直投 / fast-mode dispatch 下发，未经过 `_doFlushMessageQueue`。

## 6. 本次代码对齐了什么

1. 家庭任务列表解析：新增顶层 `familyTasks` → `handleTaskList:source:@"family"`。
2. 家庭任务字段：`awardType=FAMILY_INTIMACY` 时用 `awardCount` 作为亲密度；`extend.canDo=false` 时跳过执行，避免无效请求。
3. 庄园领奖请求体：补上抓包中实际存在的 `version` 字段。
4. 家庭页观测：解析并展示 `familyActivityIntimateNumber`、`familyDailyIntimateNumber`、`familyIntimateAwardGear`、`activityInfo` 起止时间、排名线、`familyTasks` 概览。
5. 请求侧抓包：新增 `_dispatchMessage:` Hook + 同 `callbackId` 去重，为下一次抓家庭任务请求做准备。
6. 版本：v3.5.0。

## 7. 未抓到 / 仍需确认

| 缺口 | 现状 | 如何再抓 |
| --- | --- | --- |
| 家庭任务列表请求 `operationType` | 只有 `familyTasks` 回包，没有请求 | 安装 v3.5.0，开启抓包，在「家庭」页点开任务面板并下拉刷新；若仍无请求，需用 Thor/mitmproxy 抓 HTTPS |
| 家庭任务执行（do）`operationType` | 未出现 | 在饭点点击「请客吃饭」、点「帮家人喂鸡」 |
| 家庭任务领奖（claim）`operationType` | 未出现 | 完成家庭任务后点「领取」 |
| 个人排名 / 总人数 | 只有排名线阈值 | 打开家庭页排行榜（若有）或活动排行入口 |
| 每日亲密度上限 | 未出现明确字段 | 面板/活动规则页截图或回包 |

> 安全约束：插件只发送抓包中出现过的 `operationType`；上表未确认的接口不会主动请求，也不会用猜测值填充配置。

## 8. 复现抓包的操作建议

1. 安装 v3.5.0，进入蚂蚁庄园 → 家庭页。
2. 面板点「开始抓包 60 秒」，立即：
   - 下拉刷新家庭页；
   - 打开家庭任务列表；
   - 依次点「去请客 / 去喂食 / 去捐蛋」（建议在对应可执行时段）；
   - 完成后点「领取」。
3. 导出 `capture-*.ndjson` 与 `family-candidates.ndjson`。
4. 若 `familyTask` 相关请求仍缺失，改用系统级抓包（Thor / mitmproxy）并只保留 `com.alipay.antfarm.*` 域名请求。

## 9. 第二次抓包（v3.5.0，capture-20261105-150221）

分析对象：`capture-20261105-150221.ndjson`（667 条记录，约 880 KB，15:02:21—15:03:02）。
抓包环境：已安装 v3.5.0（含 `_dispatchMessage:` 请求侧 Hook），在家庭页完成了签到领奖、捐蛋、外卖红包三个任务。

### 9.1 记录总览与差异

| 指标 | 第一次 `143022` | 第二次 `150221` |
| --- | --- | --- |
| 总记录 | 414 | 667 |
| 请求（req） | 40 | 13 |
| 回包（resp） | 374 | 654 |
| 请求侧 operationType | 6 个 | 1 个（`doFarmTask`） |
| 家庭任务请求 | 0 | **0** |
| `unknown` 回包 | 370 | 648 |

**新增 operationType：无。** 第二次的 13 个请求全部是插件自己发出的 `com.alipay.antfarm.doFarmTask`（callbackId 前缀 `rpc_manor_task_`），不是 H5 家庭页请求：

| bizKey | bizKey | bizKey |
| --- | --- | --- |
| `VIDEO_TASK` | `SHANGYEHUA_90_1` | `chouchoule_xiaritianpin` |
| `IPchouchoule_26NBAguanhuaixingdong` | `SHH_caiwenjing` | `zbfc202610` |
| `BBNC_gyg` | `FAMILY_VIEW_TASK` | `COOK` |
| `WIDGET_addzujian` | `HIRE_LOW_ACTIVITY` | `xincun2023` |
| `PAILITAO_202510` | — | — |

请求体与第一次完全一致：

```json
[{"bizKey":"...","requestType":"NORMAL","sceneCode":"ANTFARM","source":"H5","version":"1.8.2302070202.46"}]
```

这 13 个请求的回包（`15:02:21.265`—`15:02:21.338`）均为 `{taskId, taskStatus:"FINISHED", awardCount}`，说明插件自身的庄园任务链路正常；它们与家庭页任务无关。

`deliverByPageId` 回包 6 个（页面直投），与第一次相同。

### 9.2 `_dispatchMessage:` Hook 结果

- 第二次抓包中 **没有任何一条非插件请求**（req 记录 13 条，callbackId 全部以 `rpc_manor_` 开头）。
- 家庭页 RPC 的回包仍能通过 `transformResponseData:` 抓到（654 条），但请求侧一条都没有。
- 结论：**家庭页请求不经过 `PSDJsBridge/RVKJsBridge` 的实例方法 `_doFlushMessageQueue:url:`，也不经过 `_dispatchMessage:`**。v3.5.0 新增的 Hook 未命中 fast-mode 请求。

### 9.3 家庭任务回包时间线（请求侧全部缺失）

| 时间 | 行号 | 回包内容 | 对应请求 |
| --- | --- | --- | --- |
| 15:02:35.913 | `#237` | `farmTaskList` 仅 1 项：`FAMILY_SIGN_TASK`，`taskMode=TRIGGER`，`taskStatus=FINISHED`，`awardCount=1`，`sceneCode=ANTFARM_FAMILY_TASK` | 无（访问家庭页即触发完成） |
| 15:02:39.715 | `#306` | `{"success":true}` | 无 |
| 15:02:40.221 | `#307` | `{"success":true,"memo":"SUCCESS","resultCode":"100","taskStatus":"RECEIVED"}` | **领奖请求缺失** |
| 15:02:40.420 | `#318` | `familyTasks` 五项均为 `TODO`；`canDo=true` 仅 `DAILY_DONATE`、`FAMILY_SHANGOU` | 无 |
| 15:02:41.329 | `#320` | `familyActivityIntimateNumber=26`，`familyDailyIntimateNumber=4829` | 无（状态刷新） |
| 15:02:43—15:02:51 | `#336`/`#367`/`#370`/`#371`/`#384`/`#412` | 捐蛋页面：项目列表 → 资产 → 反馈 → **捐赠成功**（`donationUserRecordId`/`bizNo`/`donation`/`achievementRecords`）→ 捐赠记录 | **捐赠请求缺失**（页面为 `selfProjectDonation.html`） |
| 15:02:56.599 | `#443` | 家庭状态：`36` / `4839`；`familyBarrageList` 新增 `DODONATIONTASK intimateNum=10 @15:02:50` | 无 |
| 15:02:58.244 | `#479` | `familyTasks`：`DAILY_DONATE taskStatus=RECEIVED awardCount=10` | **领奖请求缺失** |
| 15:02:59.741 | `#485` | `{"taskId":"FAMILY_SHANGOU","awardCount":1,"taskStatus":"FINISHED","success":true}` | **执行/领奖请求缺失** |
| 15:02:59.888 | `#486` | `familyTasks`：`FAMILY_SHANGOU taskStatus=RECEIVED awardCount=1` | 无 |
| 15:03:01.045 | `#521` | `37` / `4840` | 无（状态刷新） |

### 9.4 亲密度变化归因

| 时间 | 活动亲密度 | 家庭总亲密度 | 增量 | 归因 |
| --- | --- | --- | --- | --- |
| 15:02:35（基线） | 25 | 4828 | — | 与第一次抓包结束时一致 |
| 15:02:41.329 | 26 | 4829 | **+1 / +1** | `FAMILY_SIGN_TASK` 每日签到领奖（回包 `#307 taskStatus=RECEIVED`；请求未抓到） |
| 15:02:56.599 | 36 | 4839 | **+10 / +10** | `DAILY_DONATE` 每日捐蛋（`#384` 15:02:50 捐赠成功，`familyBarrageList` 出现 `DODONATIONTASK intimateNum=10`；请求未抓到） |
| 15:03:01.045 | 37 | 4840 | **+1 / +1** | `FAMILY_SHANGOU` 外卖红包任务（`#485 taskStatus=FINISHED awardCount=1`，`#486 RECEIVED`；请求未抓到） |

本次抓包期间共 +12（25→37 / 4828→4840），三次增量都能在回包中定位，但没有一条对应的请求侧记录。

### 9.5 结论（不变）

1. **仍未抓到家庭任务执行/领奖的 `operationType`**，两次抓包（v3.4.0 与 v3.5.0）结果一致。
2. `familyTaskOperationType`、`familyTaskClaimOperationType` 继续保持**空字符串**；空配置时 `submitTask` / `claimTask` 不会发请求。
3. 面板可解析并展示家庭任务状态、`taskId` 与动作，但不据此猜测或构造请求。
4. 已知的家庭任务动作（来自回包，仅用于展示/归类）：`TREAT`（`EAT_TOGETHER`）、`HELP_FEED_PRIZE`（`FEED_ANIMAL`）、`DAILY_DONATE`（`DONATION`）、`FAMILY_TREAD_MALL`（`DONATE_STEP`）、`FAMILY_SHANGOU`（`JUMP`）。
5. `FAMILY_SIGN_TASK` 是 `taskMode=TRIGGER`，访问家庭页即完成，只需领奖；本次只观察到领奖回包。

### 9.6 下一步建议

| 方案 | 做法 | 优点 | 风险/限制 |
| --- | --- | --- | --- |
| A. HTTPS 层抓包 | Thor（iOS）或 mitmproxy/Charles + 证书，抓 `familyFeed.html` 所在域与 RPC 网关，筛选请求体含 `sceneCode:ANTFARM_FAMILY_TASK`、`taskId`、`operationType` 的 POST | 直接拿到完整请求体与 operationType，可一次补齐执行/领奖 | 支付宝可能有证书固定/双向校验；Thor 需要 TrollStore/越狱环境；抓到的请求体仍可能包含不可复现的签名参数 |
| B. 安卓无障碍版本 | 沿用已完成的 Android 无障碍自动化（点击家庭页真实按钮完成任务），不逆向 RPC | 不依赖私有接口与签名，成功率高 | 需要一台安卓设备常驻；iOS 侧无法直接复用 |
| C. 继续 iOS Hook | 追加 `+dispatchJsapiInFastMode:targetNode:responseCallback:`、`-callJsApi:url:data:responseCallback:`、`-callJsApi:url:data:callFrom:disableCheckPermission:responseCallback:` 等入口的只读记录 | 成本低，若命中可直接补齐 | 需要真机验证；盲目加 Hook 有干扰 H5 容器风险，v3.6.0 未采用 |

> 在拿到 A/C 的真实请求体之前，不会为 `familyTaskOperationType` / `familyTaskClaimOperationType` 填写任何猜测值。

## 10. v3.6.0 改动

1. 家庭任务 `taskId → 动作` 映射落到代码：`TREAT`（请客吃饭）、`HELP_FEED_PRIZE`（帮喂家人小鸡）、`DAILY_DONATE`（每日捐蛋）、`FAMILY_TREAD_MALL`（一起运动捐步）、`FAMILY_SHANGOU`（领外卖红包）；仅用于面板概览与日志归类，不生成请求。
2. 面板状态文案按第二次抓包更新：「两次抓包均只有 familyTasks 回包、无请求侧 operationType，暂不发送请求」。
3. 配置仍为空：`familyTaskOperationType`、`familyTaskClaimOperationType`、`familyTaskRequestData`、`familyTaskClaimRequestData` 未填写。
4. 抓包模块未新增 Hook（避免真机未验证的 Hook 干扰 H5 容器）；后续方案见 9.6。
