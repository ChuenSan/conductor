import AppKit
import ConductorCore
import Foundation
@preconcurrency import GhosttyKit

/// 一个真 libghostty 终端。持有 `ghostty_surface_t` 和承载它的 `TerminalHostView`，
/// 实现 ConductorCore 的引擎无关 `TerminalSurface` 生命周期协议。几何/输入逻辑也在此（host view 只转发事件）。
@MainActor
final class GhosttySurface: TerminalSurface {
    let hostView: TerminalHostView

    private var surface: ghostty_surface_t?
    private var retainedUserdata: Unmanaged<GhosttySurface>?
    private var pendingCwd: String?
    /// 待执行命令（如一键启动 codex/claude）：surface 创建后稍候发出，等 shell 起好。
    private var pendingCommand: String?
    /// 待预输入文本（不带回车，如 resume 命令）：打到提示符上，用户按 Enter 才执行。
    private var pendingTypedText: String?
    /// 待回放的内容快照路径：attach 时换用 wrapper 脚本启动（cat 快照 → exec shell）。
    var restoreContentFile: String?
    private var lastScale: CGFloat = 0
    private var lastSize: CGSize = .zero

    // ConductorCore.TerminalSurface 回调（由 SessionRegistry 注入；运行时 action 路由触发）
    var onTitleChange: ((String) -> Void)?
    var onCwdChange: ((URL) -> Void)?
    var onExit: ((Int32) -> Void)?
    /// 终端被点击时请求把"当前活动 pane"切到自己（更新模型 + 焦点环）。
    var onRequestFocus: (() -> Void)?
    /// ⌘+拖 发起整块 pane 拖拽（由 PaneContainerView 接住起拖）。
    var onBeginPaneDrag: ((NSEvent) -> Void)?
    /// 滚动条状态（total 总行 / offset 视口顶偏移 / len 视口可见行），由 ghostty SCROLLBAR action 推送。
    var onScrollbar: ((_ total: UInt64, _ offset: UInt64, _ len: UInt64) -> Void)?
    /// 搜索（由 ghostty 搜索 actions 推送）：开始(初始 needle)/匹配总数/当前项/结束。
    var onSearchStart: ((String) -> Void)?
    var onSearchTotal: ((Int) -> Void)?
    var onSearchSelected: ((Int) -> Void)?
    var onSearchEnd: (() -> Void)?
    /// 鼠标悬停在链接上（nil = 移开）。⌘点击打开由 OPEN_URL 动作兜底处理。
    var onLinkHover: ((String?) -> Void)?

    func requestFocus() { onRequestFocus?() }
    func beginPaneDrag(_ event: NSEvent) { onBeginPaneDrag?(event) }

    init() {
        hostView = TerminalHostView()
        hostView.owner = self
    }

    static func fromGhosttySurface(_ handle: ghostty_surface_t?) -> GhosttySurface? {
        guard let handle, let userdata = ghostty_surface_userdata(handle) else { return nil }
        return Unmanaged<GhosttySurface>.fromOpaque(userdata).takeUnretainedValue()
    }

    // MARK: - TerminalSurface

    func start(cwd: URL) {
        pendingCwd = cwd.path
        attachIfPossible()
    }

    /// 排入一条待执行命令：若 surface 已就绪则稍候发出，否则等 attach 后再发。
    func enqueueCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingCommand = trimmed
        flushPendingCommandIfReady()
    }

    /// 排入一段预输入文本：只打字不回车（恢复 pane 时把 resume 命令摆在提示符上，按 Enter 续聊）。
    func enqueueTypedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingTypedText = trimmed
        flushPendingCommandIfReady()
    }

    /// surface 存在时把待执行命令（粘贴 + 真回车键）和预输入文本（不回车）发出。
    /// 延迟一下让 shell 起好、画好首个提示符（内容回放的 cat 也在这窗口内完成）。
    /// 回车必须走按键通道：粘贴通道里的 "\r" 在 bracketed paste 下只是文本，
    /// zsh 会把命令留在缓冲区不执行（「resume 不自动发送」的根因）。
    private func flushPendingCommandIfReady() {
        guard surface != nil, pendingCommand != nil || pendingTypedText != nil else { return }
        let command = pendingCommand
        let typed = pendingTypedText
        pendingCommand = nil
        pendingTypedText = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            if let command {
                self?.sendText(command)
                // 粘贴和按键是两条通道，稍等粘贴消化完再回车，避免乱序
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.sendEnterKey()
                }
            }
            if let typed { self?.sendText(typed) }
        }
    }

    /// 发送一次真实的回车按键（press + release）。
    /// TUI（claude/codex）在 raw 模式下只认按键事件；shell 的 bracketed paste 同理。
    func sendEnterKey() {
        sendBareKey(keycode: 36, codepoint: 13, text: "\r")   // kVK_Return
    }

    /// 发送一次真实的 Esc 按键（快捷回复里的「拒绝/取消」）。
    func sendEscapeKey() {
        sendBareKey(keycode: 53, codepoint: 27, text: "\u{1B}")   // kVK_Escape
    }

    private func sendBareKey(keycode: UInt32, codepoint: UInt32, text: String) {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = keycode
        keyEvent.composing = false
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = codepoint
        text.withCString {
            keyEvent.text = $0
            _ = ghostty_surface_key(surface, keyEvent)
        }
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, keyEvent)
    }

    func focus() {
        if let surface { ghostty_surface_set_focus(surface, true) }
        hostView.window?.makeFirstResponder(hostView)
    }

    func close() {
        guard let surface else { return }
        self.surface = nil           // 立刻断开：后续 syncGeometry/输入都会 no-op
        hostView.owner = nil
        hostView.removeFromSuperview()
        let userdata = retainedUserdata
        retainedUserdata = nil
        // 延迟释放：先让当前渲染周期跑完，避免与 libghostty 渲染线程相撞（UAF）。
        DispatchQueue.main.async {
            ghostty_surface_free(surface)
            userdata?.release()
        }
    }

    // MARK: - Attach / geometry (host view 调用)

    /// host view 上墙后调用：若尚未创建则创建 libghostty surface。
    func attachIfPossible() {
        guard surface == nil, hostView.window != nil, let cwd = pendingCwd else { return }
        GhosttyRuntime.shared.ensureStarted()
        guard let app = GhosttyRuntime.shared.app else { return }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(hostView).toOpaque())
        )
        let userdata = Unmanaged.passRetained(self)
        config.userdata = userdata.toOpaque()
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        config.font_size = 14
        config.wait_after_command = false
        config.scale_factor = Double(hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)

        // shell：配置优先，否则用户登录 shell（$SHELL），再否则 /bin/zsh。
        let shell = ConfigStore.shared.config.terminal.shell
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"

        // 内容恢复：有待回放快照时换 wrapper 启动（cat 快照 → rm → exec 真 shell），
        // 路径与 shell 走 env 传参，避开引号/转义问题。
        var command = shell
        var envPairs: [(key: String, value: String)] = []
        if let restoreFile = restoreContentFile,
           FileManager.default.fileExists(atPath: restoreFile),
           let wrapper = ScrollbackStore.ensureWrapperScript() {
            command = wrapper
            envPairs = [("CONDUCTOR_RESTORE_FILE", restoreFile), ("CONDUCTOR_RESTORE_SHELL", shell)]
        }
        restoreContentFile = nil

        // env_vars 要求 C 字符串在 surface_new 调用期间存活：strdup 后统一释放。
        let cStrings = envPairs.map { (strdup($0.key), strdup($0.value)) }
        defer { cStrings.forEach { free($0.0); free($0.1) } }
        var envVars = cStrings.map { ghostty_env_var_s(key: $0.0, value: $0.1) }
        command.withCString { commandPointer in
            cwd.withCString { directoryPointer in
                envVars.withUnsafeMutableBufferPointer { envBuffer in
                    config.command = commandPointer
                    config.working_directory = directoryPointer
                    if !envBuffer.isEmpty {
                        config.env_vars = envBuffer.baseAddress
                        config.env_var_count = envBuffer.count
                    }
                    surface = ghostty_surface_new(app, &config)
                }
            }
        }

        guard let surface else {
            userdata.release()
            NSLog("[conductor] ghostty_surface_new failed")
            return
        }
        retainedUserdata = userdata
        syncGeometry(force: true)
        ghostty_surface_set_occlusion(surface, true)   // 可见（bool 实为 visible）
        ghostty_surface_set_focus(surface, false)
        ghostty_surface_refresh(surface)
        flushPendingCommandIfReady()
    }

    func syncGeometry(force: Bool = false) {
        guard let surface, let window = hostView.window else { return }
        let scale = window.backingScaleFactor
        if force || scale != lastScale {
            ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
            lastScale = scale
        }
        let backing = hostView.convertToBacking(NSRect(origin: .zero, size: hostView.bounds.size)).size
        let width = max(1, UInt32(backing.width.rounded(.toNearestOrAwayFromZero)))
        let height = max(1, UInt32(backing.height.rounded(.toNearestOrAwayFromZero)))
        let pixel = CGSize(width: CGFloat(width), height: CGFloat(height))
        if force || pixel != lastSize {
            ghostty_surface_set_size(surface, width, height)
            lastSize = pixel
        }
        ghostty_surface_refresh(surface)
    }

    /// 配置热更新：把最新 ghostty 配置应用到本 surface（字体/配色/padding 即时生效，不重建、不丢 scrollback）。
    func reloadConfig() {
        guard let surface, let config = GhosttyRuntime.shared.config else { return }
        ghostty_surface_update_config(surface, config)
        ghostty_surface_refresh(surface)
    }

    /// 重挂视图层级后强制重画（避免变白）。
    func forceRedraw() {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, true)   // true = 可见
        syncGeometry(force: true)
        ghostty_surface_refresh(surface)
    }

    /// 可见性同步：false 让 core 的渲染线程休眠（光标/动画停画），省 GPU/CPU。
    /// 离屏（切走的标签/工作区）与窗口被遮挡/最小化时调用；PTY 输出照常处理，回屏即新。
    func setOcclusion(_ visible: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, visible)
    }

    // MARK: - Input (host view 调用)

    func setFocused(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    func sendMouseButton(_ button: ghostty_input_mouse_button_e, state: ghostty_input_mouse_state_e, event: NSEvent) {
        guard let surface else { return }
        updateMouse(event)
        _ = ghostty_surface_mouse_button(surface, state, button, event.modifierFlags.ghosttyMods)
    }

    func scroll(_ event: NSEvent) {
        guard let surface else { return }
        let precise = event.hasPreciseScrollingDeltas
        var x = Double(event.scrollingDeltaX)
        var y = Double(event.scrollingDeltaY)
        if precise { x *= 2; y *= 2 }
        let mods = ghostty_input_scroll_mods_t(precise ? 1 : 0)
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    func updateMouse(_ event: NSEvent) {
        guard let surface else { return }
        let point = hostView.convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, Double(point.x), Double(hostView.bounds.height - point.y), event.modifierFlags.ghosttyMods)
    }

    func forwardKey(_ event: NSEvent, action: ghostty_input_action_e) {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = event.modifierFlags.ghosttyMods
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE

        if let chars = event.charactersIgnoringModifiers ?? event.characters,
           let scalar = chars.unicodeScalars.first,
           !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF) {
            keyEvent.unshifted_codepoint = scalar.value
        } else {
            keyEvent.unshifted_codepoint = 0
        }

        if action == GHOSTTY_ACTION_RELEASE {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
            return
        }

        if let text = printableText(for: event) {
            text.withCString { pointer in
                keyEvent.text = pointer
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    private func printableText(for event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty,
              let scalar = characters.unicodeScalars.first else { return nil }
        if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        if scalar.value < 0x20, event.modifierFlags.contains(.control) {
            return event.charactersIgnoringModifiers ?? characters
        }
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) {
            return nil
        }
        return characters
    }

    /// 由 read_clipboard_cb 回到主线程后调用：把系统剪贴板内容回填给 libghostty（用于 paste）。
    func completeClipboardRequest(state: UnsafeMutableRawPointer) {
        guard let surface else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        text.withCString {
            ghostty_surface_complete_clipboard_request(surface, $0, state, false)
        }
    }

    // MARK: - Runtime action routing 回调

    func handleSetTitle(_ title: String) { onTitleChange?(title) }
    func handlePwd(_ pwd: String) { onCwdChange?(URL(fileURLWithPath: pwd)) }
    func handleChildExited() { onExit?(0) }
    func handleScrollbar(total: UInt64, offset: UInt64, len: UInt64) { onScrollbar?(total, offset, len) }
    func handleSearchStart(_ needle: String) { onSearchStart?(needle) }
    func handleSearchTotal(_ total: Int) { onSearchTotal?(total) }
    func handleSearchSelected(_ selected: Int) { onSearchSelected?(selected) }
    func handleSearchEnd() { onSearchEnd?() }
    func handleMouseOverLink(_ url: String?) { onLinkHover?(url) }

    /// core 请求换鼠标指针（链接上 pointer、正文 text…）。只在鼠标确实悬在本终端时生效。
    func handleMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        guard hostView.window != nil else { return }
        let mouseInside = hostView.window.map {
            hostView.isMousePoint(hostView.convert($0.mouseLocationOutsideOfEventStream, from: nil),
                                  in: hostView.bounds)
        } ?? false
        guard mouseInside else { return }
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_POINTER: NSCursor.pointingHand.set()
        case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_CELL: NSCursor.iBeam.set()
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: NSCursor.crosshair.set()
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: NSCursor.iBeamCursorForVerticalLayout.set()
        default: NSCursor.arrow.set()
        }
    }

    /// 拖动滚动条时按像素滚动终端（drag thumb → 滚内容）。
    /// 必须带 precise 标志：否则 ghostty 把数值当滚轮「格数」（一格多行），
    /// 像素级数值会被放大成几千行，thumb 直接砸到顶/底。
    func scrollByPixels(_ dy: Double) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, 0, dy, ghostty_input_scroll_mods_t(1))
    }

    /// 按名触发 ghostty 动作（如 copy_to_clipboard / paste_from_clipboard / select_all / clear_screen）。
    @discardableResult
    func performAction(_ name: String) -> Bool {
        guard let surface else { return false }
        return name.withCString { ghostty_surface_binding_action(surface, $0, UInt(name.utf8.count)) }
    }

    var hasSelection: Bool {
        guard let surface else { return false }
        return ghostty_surface_has_selection(surface)
    }

    /// 向 surface 发送文字（搜索模式下用于输入查询）。
    func sendText(_ text: String) {
        guard let surface else { return }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
    }

    // MARK: - IME（输入法）

    /// IME 提交的整段文本（走「键入文本」通道，区别于粘贴语义的 sendText）。
    func sendTextInput(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        text.withCString { ghostty_surface_text_input(surface, $0, UInt(text.utf8.count)) }
    }

    /// 设置/清除预编辑串（组合中的拼音内联显示在光标处）；传 nil 清除。
    func setPreedit(_ text: String?) {
        guard let surface else { return }
        if let text, !text.isEmpty {
            text.withCString { ghostty_surface_preedit(surface, $0, UInt(text.utf8.count)) }
        } else {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    /// 光标格子在 surface 内的位置与大小（点单位，原点左上）。IME 候选窗定位用。
    func imeCursorRect() -> CGRect? {
        guard let surface else { return nil }
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 读取整个屏幕 + 回滚缓冲的纯文本（内容快照用）。surface 未创建（pane 从未显示）返回 nil。
    func readAllText() -> String? {
        readText(tag: GHOSTTY_POINT_SCREEN)
    }

    /// 只读当前可见视口的纯文本（Mission Control 卡片预览用，按需调用、开销小）。
    func readViewportText() -> String? {
        readText(tag: GHOSTTY_POINT_VIEWPORT)
    }

    private func readText(tag: ghostty_point_tag_e) -> String? {
        guard let surface else { return nil }
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: tag, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(
                tag: tag, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false)
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else { return nil }
        return String(
            bytes: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)),
            encoding: .utf8)
    }

    /// 当前 pane 前台进程 PID（用于识别在跑哪个 Agent）。无则 nil。
    func foregroundPID() -> Int32? {
        guard let surface else { return nil }
        let pid = ghostty_surface_foreground_pid(surface)
        return pid > 0 ? Int32(truncatingIfNeeded: pid) : nil
    }

}

extension NSEvent.ModifierFlags {
    var ghosttyMods: ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE
        if contains(.shift) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_SHIFT.rawValue)) }
        if contains(.control) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_CTRL.rawValue)) }
        if contains(.option) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_ALT.rawValue)) }
        if contains(.command) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_SUPER.rawValue)) }
        return mods
    }
}
