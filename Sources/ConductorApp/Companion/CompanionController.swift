import AppKit
import Combine
import ConductorCore
import SwiftUI

/// 桌面通知宠物的控制器：订阅 app 里**真实在线**的 agent 活动信号
/// （`thinkingPanes` / `unseenDonePanes` / `feedCenter.pending`），映射成 Core 的
/// `AgentSignal`，交给纯逻辑 `PetStateReducer` 归约出 `PetMood`，再驱动透明浮窗里的宠物。
///
/// 同时是配置中枢：观察 `ConfigStore` 的 `companion` 段（启用/模版/角落/气泡/内联审批），
/// 并把待审批请求暴露给气泡做就地「允许/拒绝」（复用 `FeedCenter`，与右侧面板/ socket 零分叉）。
///
/// 信号源**有意可替换**：今天喂 pane 世界的状态；将来 `BuiltinAgentSession`（pi）接进 app 后，
/// 只需在 `recompute()` 多并一个 `phase` 源，reducer / 视图一行不动。
@MainActor
final class CompanionController: ObservableObject {
    @Published private(set) var mood: PetMood = .idle
    @Published private(set) var bubble: String?
    @Published private(set) var pendingApproval: FeedRequest?
    @Published private(set) var config: CompanionConfig
    /// 点宠物时自增 → 视图弹一下（点击反馈）。
    @Published private(set) var pokeNonce = 0

    /// AI 完成后 agent 的**真实回复全文**：宠物直接冒出来（可展开看全文），不是"可查看结果"这种死文案。
    /// 新一轮开始干活、或窗口过期则清。
    @Published private(set) var resultText: String?
    private var resultUntil: TimeInterval?
    private var resultPaneID: String?
    private static let resultWindow: TimeInterval = 20

    /// 摸一下的临时卖萌气泡。
    private var quip: String?
    private var quipUntil: TimeInterval?

    static let windowSize = CGSize(width: 224, height: 248)
    /// 底部「精灵命中区」高度：这块归原生 NSView（拖拽 + 点击跳转）；
    /// 上方气泡/审批卡区交回 SwiftUI（按钮可点）。见 `CompanionPanelContentView.hitTest`。
    static let petZoneHeight: CGFloat = 100
    private static let frameAutosaveName = "ConductorCompanionWindow"

    private weak var coordinator: AppCoordinator?
    private let feedCenter: FeedCenter
    private var reducer = PetStateReducer()

    private var panel: NSPanel?
    /// 始终在的订阅（只观察配置，用来起停下面的"活动订阅"）。
    private var cancellables: Set<AnyCancellable> = []
    /// 仅"启用"时挂的订阅（信号源 sink）；停用即全撤，不空转。
    private var activeCancellables: Set<AnyCancellable> = []
    private var tick: Timer?

    /// 选中宠物若是 Codex 图集，这里是已加载的图集；nil = 用程序化模版渲染。
    @Published private(set) var atlasSheet: CGImage?
    /// 程序化兜底模版（atlasSheet 为 nil 时用）。
    private(set) var proceduralTemplate: PetTemplate = PetTemplateCatalog.default
    private var resolvedPetName: String = L(PetTemplateCatalog.default.nameKey)
    private var petLoadGeneration = 0

    var displayName: String {
        if let n = config.name, !n.isEmpty { return n }
        return resolvedPetName
    }

    /// 把 `config.templateID` 解析成具体渲染源（内置程序化 / 发现到的 Codex 图集）。
    private func resolvePet() {
        petLoadGeneration &+= 1
        let generation = petLoadGeneration
        let pet = CompanionPetCatalog.pet(id: config.templateID)
        let templateID = pet.id
        resolvedPetName = pet.name
        switch pet.kind {
        case let .procedural(template):
            proceduralTemplate = template
            atlasSheet = nil
        case let .atlas(url):
            if let sheet = CodexPetCatalog.preparedSheet(at: url) {
                atlasSheet = sheet
                return
            }

            // 第一次切到某个 Codex 图集时，解码 + 切 8×9 动画帧都比较贵。
            // 放到后台做，完成后再发布给 SwiftUI，避免点击设置卡片时主线程卡一下。
            DispatchQueue.global(qos: .userInitiated).async { [url, generation, templateID] in
                let sheet = CodexPetCatalog.prepareSheet(at: url)
                Task { @MainActor [weak self] in
                    guard let self,
                          self.petLoadGeneration == generation,
                          self.config.templateID == templateID else { return }
                    if let sheet {
                        self.atlasSheet = sheet
                    } else {                           // 加载失败 → 程序化兜底，不空屏
                        self.proceduralTemplate = PetTemplateCatalog.default
                        self.atlasSheet = nil
                    }
                }
            }
        }
    }

    init(coordinator: AppCoordinator, feedCenter: FeedCenter) {
        self.coordinator = coordinator
        self.feedCenter = feedCenter
        self.config = ConfigStore.shared.config.companion
    }

    // MARK: 启动 / 配置

    /// 启动调用：始终观察配置（用来起停活动订阅），按配置决定是否显示与挂载活动订阅。
    func activate() {
        guard cancellables.isEmpty else { return }   // 防重复 activate
        CodexPetCatalog.ensureDropFolder()       // 备好 ~/.config/conductor/pets/ 投放点（社区宠物丢这里即认）
        ConfigStore.shared.$config
            .map(\.companion)
            .removeDuplicates()
            .sink { [weak self] companion in MainActor.assumeIsolated { self?.applyConfig(companion) } }
            .store(in: &cancellables)
        applyConfig(config, isInitial: true)
    }

    // MARK: AI 会话通知

    private func handleNotice(paneID: String?, title: String, body: String) {
        guard CompanionConfig.shouldDeliverToPet(notifyPet: config.notifyPet) else { return }  // 伙伴通知关 → 宠物不冒通知
        let text = Self.noticeText(title: title, body: body)
        guard !text.isEmpty else { return }
        resultText = text                        // 存 agent 真实回复全文（视图里可展开）
        resultUntil = Date().timeIntervalSinceReferenceDate + Self.resultWindow
        resultPaneID = paneID
        recompute()                              // 立刻把真实回复顶上来
    }

    /// 通知气泡文案：优先正文（agent 真回复，保留全文给展开），空则用标题。可单测。
    nonisolated static func noticeText(title: String, body: String) -> String {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? title.trimmingCharacters(in: .whitespaces) : b
    }

    /// 启用时才挂：信号源 sink + 通知出口 + 周期 tick。停用时全撤——不空转、不抢占全局 onNotify。
    private func startActive() {
        guard tick == nil else { return }   // 已在跑
        // 接「AI 会话通知」总出口（onNotify 现为 @MainActor 闭包，无需 assumeIsolated）。
        NotificationManager.shared.onNotify = { [weak self] paneID, title, body in
            self?.handleNotice(paneID: paneID, title: title, body: body)
        }
        coordinator?.$thinkingPanes
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } }
            .store(in: &activeCancellables)
        coordinator?.$unseenDonePanes
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } }
            .store(in: &activeCancellables)
        feedCenter.$pending
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } }
            .store(in: &activeCancellables)
        // 周期 tick：驱动 reducer 的时序回落（庆祝→idle、idle→打盹），信号不变也要推进。
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        recompute()
    }

    private func stopActive() {
        guard tick != nil else { return }
        NotificationManager.shared.onNotify = nil   // 让出全局单槽
        activeCancellables.removeAll()
        tick?.invalidate(); tick = nil
    }

    private func applyConfig(_ new: CompanionConfig, isInitial: Bool = false) {
        let old = config
        config = new
        if isInitial || old.templateID != new.templateID { resolvePet() }
        if new.enabled {
            startActive()
            showWindowIfNeeded()
        } else {
            stopActive()
            hide()
        }
        // 角落设置变化 → 把窗口挪过去（用户手动拖动的位置由窗口自存档保留，仅此显式覆盖）。
        if !isInitial, old.corner != new.corner { repositionToCorner(new.corner) }
        if new.enabled { recompute() }
    }

    /// 菜单/设置开关：翻转 enabled 并落盘（经 coordinator → ConfigStore → 回调 applyConfig）。
    func toggleEnabled() {
        var cfg = ConfigStore.shared.config
        cfg.companion.enabled.toggle()
        coordinator?.applyConfig(cfg)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: 窗口

    private func showWindowIfNeeded() {
        let p = panel ?? makePanel()
        if !p.isVisible { p.orderFrontRegardless() }
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = CompanionPanelContentView(controller: self)
        p.setFrameAutosaveName(Self.frameAutosaveName)
        panel = p
        if p.frame.origin == .zero { repositionToCorner(config.corner) }   // 没有存档位置 → 落到配置角落
        return p
    }

    private func repositionToCorner(_ corner: CompanionConfig.Corner) {
        let p = panel ?? makePanel()
        guard let vf = NSScreen.main?.visibleFrame else { return }
        let m: CGFloat = 24, s = Self.windowSize
        let x = (corner == .topLeft || corner == .bottomLeft) ? vf.minX + m : vf.maxX - s.width - m
        let y = (corner == .topLeft || corner == .topRight) ? vf.maxY - s.height - m : vf.minY + m
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.saveFrame(usingName: Self.frameAutosaveName)
    }

    // MARK: 信号 → 心情

    /// 把 pane 世界的三组状态压成一帧 `AgentSignal`（纯函数，可单测）。
    nonisolated static func signal(thinking: Bool, done: Bool, pending: Int) -> AgentSignal {
        let activity: AgentSignal.Activity
        if thinking {
            activity = .working
        } else if done {
            activity = .ready
        } else {
            activity = .idle
        }
        return AgentSignal(activity: activity, pendingApprovals: pending)
    }

    private func recompute() {
        guard let coordinator else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let pending = feedCenter.pending.count
        pendingApproval = feedCenter.pending.first
        let signal = Self.signal(thinking: !coordinator.thinkingPanes.isEmpty,
                                 done: !coordinator.unseenDonePanes.isEmpty,
                                 pending: pending)
        let newMood = reducer.reduce(signal, now: now)
        if newMood != mood { mood = newMood }

        // 结果回复：新一轮开始干活 → 旧结果作废；窗口过期 → 清。
        if signal.activity == .working {
            resultText = nil; resultUntil = nil; resultPaneID = nil
        } else if let until = resultUntil, now >= until {
            resultText = nil; resultUntil = nil; resultPaneID = nil
        }

        // 普通气泡（次于结果回复，视图里结果优先）：摸一下的 quip（新鲜）> 心情文案。
        let quipText = (quipUntil.map { now < $0 } ?? false) ? quip : nil
        let moodText = config.speechBubbles
            ? bubbleText(for: newMood, coordinator: coordinator, pending: pending) : nil
        let newBubble = quipText ?? moodText
        if newBubble != bubble { bubble = newBubble }
    }

    private func bubbleText(for mood: PetMood, coordinator: AppCoordinator, pending: Int) -> String? {
        switch mood {
        case .needsYou:
            return pending > 1 ? L("有 %ld 个待批准", pending) : L("需要你批准")
        case .thinking:
            if let title = firstTitle(in: coordinator.thinkingPanes, coordinator: coordinator) {
                return L("%@ 干活中…", title)
            }
            return L("干活中…")
        case .celebrating:
            if let title = firstTitle(in: coordinator.unseenDonePanes, coordinator: coordinator) {
                return L("%@ 跑完了", title)
            }
            return L("跑完了")
        case .sad:
            return L("出错了")
        case .idle, .sleeping:
            return nil
        }
    }

    private func firstTitle(in panes: Set<PaneID>, coordinator: AppCoordinator) -> String? {
        guard let pane = panes.sorted(by: { $0.value < $1.value }).first else { return nil }
        return coordinator.paneTitles[pane]
    }

    // MARK: 交互

    /// 点宠物本体：弹一下（反馈）+ 拉前台 + 跳到最值得看处
    /// （刚通知的会话→那个 pane；跑完→那个 pane；在思考→那个 pane；都没有→摸一下回应）。
    func handleTap() {
        pokeNonce &+= 1
        guard let coordinator else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let pid = resultPaneID, !pid.isEmpty {
            coordinator.revealPane(PaneID(pid))
        } else if let pane = coordinator.unseenDonePanes.sorted(by: { $0.value < $1.value }).first {
            coordinator.revealPane(pane)
        } else if let pane = coordinator.thinkingPanes.sorted(by: { $0.value < $1.value }).first {
            coordinator.revealPane(pane)
        } else {
            poke()
        }
    }

    /// 摸一下的回应：短暂卖萌气泡（弹一下由 handleTap 的 pokeNonce 触发）。
    private func poke() {
        guard config.speechBubbles else { return }
        quip = [L("在呢"), L("嗯?"), L("喵~"), L("戳啥")].randomElement() ?? L("在呢")
        quipUntil = Date().timeIntervalSinceReferenceDate + 1.6
        recompute()
    }

    /// 气泡里就地处置当前待审批请求（复用 FeedCenter，与右侧面板/socket 同一套闸）。
    func resolve(_ decision: FeedDecision) {
        guard let req = pendingApproval else { return }
        _ = feedCenter.resolve(id: req.id, decision: decision)   // recompute 由 feedCenter.$pending 回调触发
    }

    // MARK: 右键菜单动作

    func availablePets() -> [CompanionPet] { CompanionPetCatalog.all() }
    var selectedPetID: String { config.templateID }

    func selectPet(id: String) {
        guard config.templateID != id else { return }
        var cfg = ConfigStore.shared.config
        cfg.companion.templateID = id
        coordinator?.applyConfig(cfg)
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        coordinator?.openSettings()
    }

    func hidePet() {
        var cfg = ConfigStore.shared.config
        cfg.companion.enabled = false
        coordinator?.applyConfig(cfg)
    }
}

/// 浮窗内容视图：**底部精灵区**原生处理拖拽（`performDrag`，窗口服务器整窗平滑移动，
/// 无 setFrameOrigin 反馈环 → 不闪）与点击；**上方气泡/审批卡区**把事件交回 SwiftUI（按钮可点）。
private final class CompanionPanelContentView: NSView {
    private weak var controller: CompanionController?
    private var didDrag = false

    init(controller: CompanionController) {
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: CompanionController.windowSize))
        let host = NSHostingView(rootView: CompanionView(controller: controller))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if local.y <= CompanionController.petZoneHeight { return self }   // 精灵区：原生
        return super.hitTest(point)                                        // 气泡/审批卡区：SwiftUI
    }

    override func mouseDown(with event: NSEvent) { didDrag = false }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        didDrag = true
        window?.performDrag(with: event)     // 原生拖拽，平滑无闪
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { controller?.handleTap() }
    }

    // 右键/Ctrl 点 → 上下文菜单（换宠物 / 设置 / 隐藏）。
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let controller else { return nil }
        let menu = NSMenu()

        let petsItem = NSMenuItem(title: L("换宠物"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for pet in controller.availablePets() {
            let item = NSMenuItem(title: pet.name, action: #selector(selectPetItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.id
            item.state = (pet.id == controller.selectedPetID) ? .on : .off
            sub.addItem(item)
        }
        petsItem.submenu = sub
        menu.addItem(petsItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: L("伙伴设置…"), action: #selector(openSettingsItem), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let hide = NSMenuItem(title: L("隐藏伙伴"), action: #selector(hideItem), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    @objc private func selectPetItem(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { controller?.selectPet(id: id) }
    }
    @objc private func openSettingsItem() { controller?.openSettings() }
    @objc private func hideItem() { controller?.hidePet() }
}
