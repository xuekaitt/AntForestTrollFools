package com.antmanor.automation

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import kotlin.random.Random

/**
 * 页面状态机。
 *
 * 蚂蚁庄园主场景与家庭小屋使用 canvas 渲染，无障碍节点树里没有可点击元素，
 * 因此主场景动作走「归一化坐标热区点击」；答题、奖励弹层等 H5 弹层仍走节点文本识别。
 * 不做任何接口调用、脚本注入或风控绕过。
 */
class ManorAutomationEngine(
    private val service: ManorAccessibilityService,
    private val config: ManorConfig
) {

    enum class Screen {
        UNKNOWN, MANOR_MAIN, FAMILY_ROOM, FAMILY_TASKS, TASK_PAGE, QUIZ, SUB_PAGE, OTHER_APP
    }

    private val handler = Handler(Looper.getMainLooper())
    private val state = ManorState.get(service)
    private val selectors = ManorSelectors.load(service)
    private val sceneActions = SceneHotspots.load(service)

    private val pending = ArrayDeque<SceneAction>()

    private var running = false
    private var steps = 0
    private var lastScanAt = 0L
    private var lastActionAt = 0L
    private var cooldownMs = 0L
    private var screenEnteredAt = 0L
    private var currentScreen = Screen.UNKNOWN
    private var backAttempts = 0
    private var launchedAlipayAt = 0L
    private var launchAttempts = 0
    private var quizAnsweredAt = 0L
    private var popupClicks = 0
    private var quizOpened = false
    private var sawAlipay = false
    private var engineStartedAt = 0L
    private var navAttempts = 0
    private var loggedWaitingManor = false
    private var familySigninTappedAt = 0L
    private var familyEntryIntimacy = -1
    private var familySigninCounted = false
    private var familyTaskKey: String? = null
    private var familyTaskTitle = ""
    private var familyTaskClickedAt = 0L
    private var familyTaskIntimacyBefore = 0
    private val familyVisited = HashSet<String>()
    private var familyNavClickedAt = 0L
    private var familyNavAttempts = 0

    private val tickRunnable = Runnable { tick() }

    val isRunning: Boolean
        get() = running

    fun start() {
        if (running) return
        val snapshot = state.snapshot()
        if (!config.enabled) {
            log("总开关关闭，未启动自动任务")
            return
        }
        if (!ManorDomain.activityActive(config)) {
            log("当前不在活动期（${ManorDomain.activityWindowText(config)}），未启动")
            return
        }
        if (snapshot.todayTaskCount >= config.dailyTaskLimit) {
            log("今日任务数已达上限 ${config.dailyTaskLimit}，未启动")
            return
        }
        if (config.dailyIntimacyCap > 0 && snapshot.todayGained >= config.dailyIntimacyCap) {
            log("今日亲密度已达上限 ${config.dailyIntimacyCap}，未启动")
            return
        }

        pending.clear()
        for (action in sceneActions) {
            if (!state.isSubmitted(SCENE_PREFIX + action.id)) {
                pending.addLast(action)
            } else {
                log("跳过今日已完成热区：${action.label}")
            }
        }
        if (pending.isEmpty()) {
            log("今日热区任务已全部执行，无需重复运行")
            state.setLastRunStatus("已停止：今日热区任务已完成")
            return
        }

        running = true
        steps = 0
        lastActionAt = 0L
        cooldownMs = config.minActionIntervalSec * 1000L
        lastScanAt = 0L
        backAttempts = 0
        navAttempts = 0
        sawAlipay = false
        engineStartedAt = SystemClock.elapsedRealtime()
        launchedAlipayAt = 0L
        launchAttempts = 0
        quizAnsweredAt = 0L
        quizOpened = false
        popupClicks = 0
        loggedWaitingManor = false
        familySigninTappedAt = 0L
        familyEntryIntimacy = -1
        familySigninCounted = false
        familyTaskKey = null
        familyTaskTitle = ""
        familyTaskClickedAt = 0L
        familyTaskIntimacyBefore = 0
        familyVisited.clear()
        familyNavClickedAt = 0L
        familyNavAttempts = 0
        currentScreen = Screen.UNKNOWN
        screenEnteredAt = SystemClock.elapsedRealtime()

        val levelText = if (config.executionLevel == ManorConfig.LEVEL_STANDARD) "标准模式" else "安全模式"
        log(
            "开始运行：$levelText，待执行热区 ${pending.size} 个，" +
                "最小操作间隔 ${config.minActionIntervalSec}s"
        )
        updateNotifier("运行中")
        if (config.autoNavigate) {
            log("等待支付宝进入前台（由主界面发起 scheme 直达蚂蚁庄园）")
        } else {
            log("自动导航已关闭：请手动打开支付宝并进入蚂蚁庄园页面")
        }
        schedule(1200L)
    }

    fun stop(reason: String, blocked: Boolean = false) {
        if (!running) {
            log("当前未在运行：$reason")
            return
        }
        running = false
        handler.removeCallbacks(tickRunnable)
        val stoppedInFamilyDrawer = currentScreen == Screen.FAMILY_TASKS
        currentScreen = Screen.UNKNOWN
        val prefix = if (blocked) "已阻断" else "已停止"
        log("$prefix：$reason")
        state.setLastRunStatus("$prefix：$reason")
        // 停在任务抽屉里会挡住用户界面，正常结束时退回庄园场景；风控阻断时不额外操作
        if (!blocked && stoppedInFamilyDrawer) {
            service.back()
        }
        StatusNotifier.stop(service)
        service.onEngineFinished()
    }

    private fun launchAlipay() {
        if (!AlipayLauncher.open(service)) {
            log("未找到支付宝（${ManorSelectors.ALIPAY_PACKAGE}），请确认已安装")
            return
        }
        launchedAlipayAt = SystemClock.elapsedRealtime()
        launchAttempts++
        if (launchAttempts == 1) {
            log("已请求打开支付宝")
        } else if (launchAttempts >= MAX_LAUNCH_ATTEMPTS) {
            log("无法自动切到支付宝：请手动打开支付宝并进入蚂蚁庄园，自动化会继续识别")
        }
    }

    private fun tick() {
        if (!running) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastScanAt < config.scanIntervalMs) {
            schedule()
            return
        }
        lastScanAt = now

        if (!ManorConfig.load(service).enabled) {
            stop("总开关已关闭")
            return
        }
        if (state.snapshot().todayTaskCount >= config.dailyTaskLimit) {
            stop("今日任务数已达上限（${config.dailyTaskLimit}）")
            return
        }
        if (++steps > config.maxStepsPerRun) {
            stop("单次运行步数超过 ${config.maxStepsPerRun}，疑似循环，已停止")
            return
        }

        val root = service.currentRoot()
        if (root == null) {
            schedule()
            return
        }

        val texts = NodeUtils.collectTexts(root)
        val pkg = root.packageName?.toString().orEmpty()
        val risk = RiskGuard.hit(texts, selectors.riskKeywords)
        if (risk != null) {
            stop("检测到风控/验证页面（关键词：$risk），立即停止，不做任何绕过尝试", blocked = true)
            return
        }

        val screen = classify(texts, pkg)
        if (pkg == ManorSelectors.ALIPAY_PACKAGE) sawAlipay = true
        if (screen != currentScreen) {
            currentScreen = screen
            screenEnteredAt = now
            if (screen == Screen.MANOR_MAIN) backAttempts = 0
            if (screen == Screen.FAMILY_ROOM || screen == Screen.FAMILY_TASKS) {
                if (pending.removeAll { it.id == "family_room" }) {
                    // 不写 scene:family_room 的今日去重：家庭任务每天会刷新，
                    // 进入家庭的重复判断交给 family:<task> 的提交键，避免第二天之前再也进不去。
                    log("已进入家庭页，家庭入口热区完成")
                }
            }
        }

        observe(texts, pkg)

        // 家庭任务点开后跳到了任务详情页：等页面停留时间，然后返回家庭抽屉并结算。
        if (familyTaskKey != null && screen != Screen.FAMILY_TASKS && screen != Screen.FAMILY_ROOM &&
            screen != Screen.OTHER_APP && screen != Screen.UNKNOWN
        ) {
            handleFamilyTaskReturn(now)
            return
        }

        when (screen) {
            Screen.OTHER_APP -> handleOtherApp(pkg, now)
            Screen.MANOR_MAIN -> handleManorMain(root, now)
            Screen.FAMILY_ROOM -> handleFamilyRoom(root, now)
            Screen.FAMILY_TASKS -> handleFamilyTasks(root, now)
            Screen.TASK_PAGE -> handleTaskPage(root, now)
            Screen.QUIZ -> handleQuiz(root, texts, now)
            Screen.SUB_PAGE -> handleSubPage(root, now)
            Screen.UNKNOWN -> if (handlePopup(root, now)) return
        }

        if (!running) return
        if (now - screenEnteredAt > config.pageTimeoutSec * 1000L &&
            (screen == Screen.SUB_PAGE || screen == Screen.OTHER_APP)
        ) {
            stop("页面停留超时（${screenName()}），请确认已进入蚂蚁庄园页面")
            return
        }
        if (running) schedule()
    }

    /**
     * 屏幕分类：
     * - 蚂蚁庄园主场景与家庭小屋是 canvas，节点树里只有标题/返回/更多/关闭这几个系统文案；
     * - 饲料任务页、答题页是 H5，会出现业务文案。
     */
    private fun classify(texts: List<String>, pkg: String): Screen {
        if (pkg != ManorSelectors.ALIPAY_PACKAGE) return Screen.OTHER_APP
        // 家庭任务抽屉里同时有「去完成」按钮，必须先于 TASK_PAGE 判断。
        if (texts.any { text -> selectors.familyTaskListMarkers.any { text.contains(it) } }) {
            return Screen.FAMILY_TASKS
        }
        if (texts.any { text -> selectors.quizMarkers.any { text.contains(it) } }) return Screen.QUIZ
        if (texts.any { text -> selectors.taskPageMarkers.any { text.contains(it) } }) return Screen.TASK_PAGE
        if (texts.any { text -> selectors.familyRoomMarkers.any { text.contains(it) } }) {
            return Screen.FAMILY_ROOM
        }
        // canvas 页只暴露标题栏文案；只要标题是「蚂蚁庄园」且没有任务页/答题页标记，就按主场景处理。
        if (texts.any { it == "蚂蚁庄园" }) return Screen.MANOR_MAIN
        return Screen.SUB_PAGE
    }

    private fun handleOtherApp(pkg: String, now: Long) {
        if (pkg == service.packageName) {
            // 已经退回本应用：若之前确实进过支付宝，说明被返回键关掉了，直接结束。
            // 启动后的前几秒内本应用还可能是前台，不判为“退出”。
            if (sawAlipay && now - engineStartedAt > 6000L) {
                stop("已退出支付宝，运行结束（请重新打开支付宝后再次运行）")
            } else if (!loggedWaitingManor && now - engineStartedAt > 6000L) {
                log("等待支付宝进入前台…")
                loggedWaitingManor = true
            }
            return
        }
        if (!config.autoNavigate) {
            if (!loggedWaitingManor) {
                log("未检测到支付宝前台，等待用户手动打开蚂蚁庄园")
                loggedWaitingManor = true
            }
            return
        }
        if (launchedAlipayAt != 0L && now - launchedAlipayAt < 8000L) return
        if (launchedAlipayAt == 0L && now - screenEnteredAt < 3000L) return
        if (launchAttempts >= MAX_LAUNCH_ATTEMPTS) return
        launchAlipay()
        screenEnteredAt = now
    }

    private fun handleManorMain(root: AccessibilityNodeInfo, now: Long) {
        // 弹层优先：canvas 弹层不可读，只处理文本弹层
        if (handlePopup(root, now)) return

        val next = pending.firstOrNull()
        if (next == null) {
            stop("今日热区任务已全部执行完成")
            return
        }
        if (next.id == "family_room") {
            if (familyNavClickedAt > 0L) {
                // 刚点过家庭入口，给 H5 3~8 秒转场时间；期间不要重复点击
                if (now - familyNavClickedAt < 9000L) return
                if (familyNavAttempts >= 2) {
                    pending.removeFirst()
                    familyNavClickedAt = 0L
                    log("连续 $familyNavAttempts 次点击后仍未进入家庭页，跳过家庭入口")
                    return
                }
            } else if (now - screenEnteredAt < 5000L) {
                // 首次进入庄园主场景先等 H5 加载完成，避免点在加载中的空白画面
                return
            }
            if (waitCooldown(now)) return
            if (!GestureTap.tapRatio(service, next.x, next.y)) {
                log("家庭入口点击失败，下一轮重试")
                return
            }
            markAction(now)
            familyNavAttempts++
            familyNavClickedAt = now
            log(
                "点击热区：${next.label}（第 $familyNavAttempts 次，" +
                    "x=${"%.3f".format(next.x)}, y=${"%.3f".format(next.y)}），等待家庭页加载"
            )
            return
        }
        if (waitCooldown(now)) return
        if (!GestureTap.tapRatio(service, next.x, next.y)) {
            log("热区点击失败（${next.label}），下一轮重试")
            return
        }
        markAction(now)
        pending.removeFirst()
        state.markSubmitted(SCENE_PREFIX + next.id)
        log("点击热区：${next.label}（x=${"%.3f".format(next.x)}, y=${"%.3f".format(next.y)}）")
        screenEnteredAt = now
        schedule(next.settleMs)
    }

    /**
     * 家庭小屋（canvas）。节点树里没有「立即签到」按钮文字，只能按比例点击；
     * 真机实测点完签到会同时展开亲密度任务抽屉，抽屉里的任务文案与按钮是可读节点。
     */
    private fun handleFamilyRoom(root: AccessibilityNodeInfo, now: Long) {
        if (handleFamilyPopup(root, now)) return
        if (now - screenEnteredAt < 1500L) return
        if (familySigninTappedAt == 0L) {
            if (waitCooldown(now)) return
            familyEntryIntimacy = state.snapshot().todayGained
            if (!GestureTap.tapRatio(service, FAMILY_SIGNIN_X, FAMILY_SIGNIN_Y)) {
                log("家庭页「立即签到」点击失败，下一轮重试")
                return
            }
            familySigninTappedAt = now
            markAction(now)
            log("点击家庭页「立即签到」（实测会同时展开亲密度任务抽屉）")
            schedule(3000L)
            return
        }
        // 签到后 8 秒仍未出现任务抽屉：退回上一页，避免在空白页空转
        if (now - familySigninTappedAt > 8000L) {
            if (backAttempts >= MAX_BACK_ATTEMPTS) {
                stop("家庭页签到后未出现任务抽屉，已停止")
                return
            }
            backAttempts++
            log("签到后仍未出现任务抽屉，返回上一页（第 $backAttempts 次）")
            service.back()
            markAction(now)
            schedule(1800L)
        }
    }

    /** 家庭页弹层：优先按「跳过/关闭」文字，其次用中心正方形关闭按钮启发式。 */
    private fun handleFamilyPopup(root: AccessibilityNodeInfo, now: Long): Boolean {
        val dismiss = NodeUtils.findByExactTexts(root, selectors.popupDismissTexts)
        if (dismiss != null) {
            val label = NodeUtils.labelOf(dismiss)
            if (NodeUtils.clickNode(service, dismiss)) {
                markAction(now)
                log("关闭家庭页弹窗「${label.ifBlank { "跳过/关闭" }}」")
                return true
            }
        }
        val close = NodeUtils.findCenterCloseButton(root)
        if (close != null && NodeUtils.clickNode(service, close)) {
            markAction(now)
            log("点击家庭页弹层中心关闭按钮（正方形启发式）")
            return true
        }
        return false
    }

    /**
     * 亲密度任务抽屉。任务卡片是 H5 节点：
     * 标题（含「可得N亲密度」）+ 按钮（去完成/去捐蛋/去请客/暂无小鸡 可喂…）。
     */
    private fun handleFamilyTasks(root: AccessibilityNodeInfo, now: Long) {
        if (familyTaskKey != null) {
            // 点击后页面没跳转（按钮实际不可用），超时后清掉，避免死等
            if (now - familyTaskClickedAt > config.taskDwellSec * 1000L + 3000L) {
                log("任务「$familyTaskTitle」点击后页面未跳转，本次不计入")
                familyTaskKey = null
            }
            return
        }
        if (now - screenEnteredAt < 800L) return
        if (!familySigninCounted && familySigninTappedAt > 0L && familyEntryIntimacy >= 0) {
            familySigninCounted = true
            val delta = state.snapshot().todayGained - familyEntryIntimacy
            if (delta > 0) {
                state.recordTaskCompleted()
                state.markSubmitted("family:signin:" + state.snapshot().date)
                log("家庭签到计入任务：亲密度 +$delta，今日任务 ${state.snapshot().todayTaskCount}/${config.dailyTaskLimit}")
                updateNotifier("运行中")
            }
        }

        val candidates = TaskScanner.scan(root, selectors)
        for (candidate in candidates) {
            val blocked = candidate.blockedReason ?: continue
            if (familyVisited.add("family-skip:" + candidate.key)) {
                log("跳过家庭任务「${candidate.title}」：$blocked")
            }
        }
        val claimable = candidates.filter { candidate ->
            candidate.blockedReason == null && candidate.kind == TaskKind.CLAIM &&
                !state.isSubmitted("family:" + candidate.key)
        }
        val todo = candidates.filter { candidate ->
            candidate.blockedReason == null && candidate.kind == TaskKind.TODO &&
                !state.isSubmitted("family:" + candidate.key) &&
                !familyVisited.contains("family:" + candidate.key)
        }

        if (waitCooldown(now)) return
        val next = claimable.firstOrNull() ?: todo.firstOrNull()
        if (next == null) {
            if (now - screenEnteredAt >= 4000L) {
                stop("家庭任务扫描完成：今日没有新的可执行亲密度任务（当前亲密度 ${state.snapshot().todayGained}）")
            }
            return
        }
        if (config.executionLevel == ManorConfig.LEVEL_SAFE && next.kind == TaskKind.TODO) {
            stop("安全模式：已完成家庭签到，发现 ${todo.size} 个需进入页面的任务，按要求未执行")
            return
        }
        if (!NodeUtils.clickNode(service, next.targetNode)) {
            log("点击家庭任务「${next.title}」失败，下一轮重试")
            return
        }
        markAction(now)
        familyVisited.add("family:" + next.key)
        familyTaskKey = "family:" + next.key
        familyTaskTitle = next.title
        familyTaskClickedAt = now
        familyTaskIntimacyBefore = state.snapshot().todayGained
        log("执行家庭任务「${next.title}」（${next.actionText}）")
        schedule(2500L)
    }

    /** 任务页停留结束 → 返回家庭抽屉，按亲密度增量决定是否计入任务数。 */
    private fun handleFamilyTaskReturn(now: Long) {
        val dwell = config.taskDwellSec * 1000L
        if (now - familyTaskClickedAt < dwell) {
            schedule(dwell - (now - familyTaskClickedAt) + 500L)
            return
        }
        service.back()
        markAction(now)
        val gained = state.snapshot().todayGained - familyTaskIntimacyBefore
        if (gained > 0) {
            state.recordTaskCompleted()
            log(
                "家庭任务「$familyTaskTitle」完成：亲密度 +$gained，" +
                    "今日任务 ${state.snapshot().todayTaskCount}/${config.dailyTaskLimit}"
            )
        } else {
            log("已返回家庭页：任务「$familyTaskTitle」未检测到亲密度增加，未计入任务数")
        }
        familyTaskKey?.let { state.markSubmitted(it) }
        familyTaskKey = null
        familyTaskTitle = ""
        updateNotifier("运行中")
        schedule(2000L)
    }

    private fun handleQuiz(root: AccessibilityNodeInfo, texts: List<String>, now: Long) {
        if (handlePopup(root, now)) return
        // 题库预告页只能看答案，没有可作答的选项，直接退回。
        if (texts.any { text -> selectors.quizPreviewMarkers.any { text.contains(it) } }) {
            handleSubPage(root, now)
            return
        }
        if (now - quizAnsweredAt < 4000L) return
        if (waitCooldown(now)) return
        val option = NodeUtils.findQuizOption(root, selectors.quizOptionWords)
        if (option == null) {
            // 已答完但页面仍停留（结果页无选项）：稍候退回任务页/主场景，避免空转。
            if (quizAnsweredAt > 0L && now - quizAnsweredAt > 5000L) {
                handleSubPage(root, now)
            }
            return
        }
        if (NodeUtils.clickNode(service, option)) {
            quizAnsweredAt = now
            markAction(now)
            log("答题：选择「${NodeUtils.labelOf(option)}」")
            schedule(2500L)
        } else {
            log("答题选项点击失败，稍后重试")
        }
    }

    /**
     * 饲料任务页（H5，文本可读）：先领取今日饲料，再进入庄园小课堂答题，最后返回主场景。
     */
    private fun handleTaskPage(root: AccessibilityNodeInfo, now: Long) {
        if (handlePopup(root, now)) return
        if (waitCooldown(now)) return
        if (!quizOpened) {
            val entry = NodeUtils.findByExactTexts(root, selectors.quizEntryTexts)
            if (entry != null && NodeUtils.clickNode(service, entry)) {
                quizOpened = true
                markAction(now)
                log("进入庄园小课堂答题")
                schedule(2500L)
                return
            }
        }
        handleSubPage(root, now)
    }

    /** 非主场景时：优先点击首页「蚂蚁庄园」入口，找不到才返回上一页。 */
    private fun handleSubPage(root: AccessibilityNodeInfo, now: Long) {
        if (now - screenEnteredAt < 2500L) return
        if (waitCooldown(now)) return
        if (navAttempts < MAX_NAV_ATTEMPTS) {
            val entry = NodeUtils.findByExactTexts(root, selectors.manorTitleTexts)
                ?: NodeUtils.findByDescriptions(root, selectors.manorTitleTexts)
            if (entry != null && NodeUtils.clickNode(service, entry)) {
                navAttempts++
                markAction(now)
                log("点击「蚂蚁庄园」入口进入庄园")
                schedule(3000L)
                return
            }
        }
        if (backAttempts >= MAX_BACK_ATTEMPTS) {
            stop("连续返回 $backAttempts 次仍未进入蚂蚁庄园主场景")
            return
        }
        backAttempts++
        service.back()
        markAction(now)
        log("返回上一页（第 $backAttempts 次）")
        schedule(1800L)
    }

    /** 文本弹层：先尝试领取类按钮，再兜底关闭，返回 true 表示本次已处理。 */
    private fun handlePopup(root: AccessibilityNodeInfo, now: Long): Boolean {
        if (popupClicks >= MAX_POPUP_CLICKS) return false
        if (waitCooldown(now)) return false
        val claim = NodeUtils.findByExactTexts(root, selectors.popupTexts)
        if (claim != null) {
            if (!NodeUtils.clickNode(service, claim)) return false
            popupClicks++
            markAction(now)
            state.recordTaskCompleted()
            log(
                "点击弹层按钮「${NodeUtils.labelOf(claim)}」，今日任务 " +
                    "${state.snapshot().todayTaskCount}/${config.dailyTaskLimit}"
            )
            updateNotifier("运行中")
            return true
        }
        val dismiss = NodeUtils.findByExactTexts(root, selectors.popupDismissTexts)
        if (dismiss != null) {
            if (!NodeUtils.clickNode(service, dismiss)) return false
            markAction(now)
            log("关闭弹层「${NodeUtils.labelOf(dismiss)}」")
            return true
        }
        return false
    }

    private fun observe(texts: List<String>, pkg: String) {
        if (pkg != ManorSelectors.ALIPAY_PACKAGE) return
        RankParser.parseTodayIntimacy(texts)?.let { state.setGainedAtLeast(it) }
        val parsed = RankParser.parseRank(texts)
        if (parsed != null) {
            val (rank, total) = parsed
            state.setRank(rank, total)
        }
    }

    private fun waitCooldown(now: Long): Boolean {
        if (lastActionAt <= 0L) return false
        return now - lastActionAt < cooldownMs
    }

    /** 记录一次真实点击，并在最小间隔上叠加最多约 1/3 的随机抖动。 */
    private fun markAction(now: Long) {
        lastActionAt = now
        val base = config.minActionIntervalSec * 1000L
        val jitter = Random.nextLong(0L, base / 3L + 1L)
        cooldownMs = base + jitter
    }

    private fun schedule(delayMs: Long = config.scanIntervalMs) {
        handler.removeCallbacks(tickRunnable)
        handler.postDelayed(tickRunnable, delayMs)
    }

    private fun updateNotifier(stateText: String) {
        val snapshot = state.snapshot()
        StatusNotifier.startOrUpdate(
            service,
            "$stateText · 今日任务 ${snapshot.todayTaskCount}/${config.dailyTaskLimit}" +
                " · 剩余热区 ${pending.size}"
        )
    }

    private fun screenName(): String = when (currentScreen) {
        Screen.MANOR_MAIN -> "蚂蚁庄园主场景"
        Screen.FAMILY_ROOM -> "家庭小屋"
        Screen.FAMILY_TASKS -> "家庭亲密度任务抽屉"
        Screen.TASK_PAGE -> "饲料任务页"
        Screen.QUIZ -> "答题页"
        Screen.SUB_PAGE -> "庄园子页面"
        Screen.OTHER_APP -> "其他应用"
        Screen.UNKNOWN -> "未知页面"
    }

    private fun log(message: String) {
        LogStore.append(message)
    }

    private companion object {
        const val SCENE_PREFIX = "scene:"
        const val MAX_BACK_ATTEMPTS = 2
        const val MAX_NAV_ATTEMPTS = 3
        const val MAX_POPUP_CLICKS = 12
        const val MAX_LAUNCH_ATTEMPTS = 3
        // 家庭小屋底部「立即签到」按钮，真机 1080×2640 标定（归一化比例）
        const val FAMILY_SIGNIN_X = 0.486f
        const val FAMILY_SIGNIN_Y = 0.903f
    }
}
