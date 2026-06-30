import AppKit

enum PaneHeaderActionPresentation {
    static let primaryActions: [PaneContextAction] = [.splitRight, .splitDown, .zoom, .close]
    static let moreActions: [PaneContextAction] = [.copy, .paste, .selectAll, .clear, .copyCwd, .openInFinder, .commandLog, .exportText]

    static func title(for action: PaneContextAction) -> String {
        switch action {
        case .copy: return L("复制")
        case .paste: return L("粘贴")
        case .selectAll: return L("全选")
        case .clear: return L("清屏")
        case .splitRight: return L("向右分屏")
        case .splitDown: return L("向下分屏")
        case .zoom: return L("放大 / 还原")
        case .copyCwd: return L("复制路径")
        case .openInFinder: return L("在 Finder 中显示")
        case .exportText: return L("导出输出为文本…")
        case .commandLog: return L("命令记录…")
        case .close: return L("关闭面板")
        }
    }

    static func systemImage(for action: PaneContextAction) -> String {
        switch action {
        case .copy: return "doc.on.doc"
        case .paste: return "clipboard"
        case .selectAll: return "checklist"
        case .clear: return "eraser"
        case .splitRight: return "rectangle.split.2x1"
        case .splitDown: return "rectangle.split.1x2"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        case .copyCwd: return "doc.text"
        case .openInFinder: return "folder"
        case .exportText: return "square.and.arrow.down"
        case .commandLog: return "list.bullet.rectangle.portrait"
        case .close: return "xmark"
        }
    }

    static func commandID(for action: PaneContextAction) -> String {
        switch action {
        case .copy: return "copyPane"
        case .paste: return "pastePane"
        case .selectAll: return "selectAllPane"
        case .clear: return "clearPane"
        case .splitRight: return "splitRight"
        case .splitDown: return "splitDown"
        case .zoom: return "toggleZoom"
        case .copyCwd: return "copyPaneCwd"
        case .openInFinder: return "openPaneInFinder"
        case .exportText: return "exportPaneText"
        case .commandLog: return "openPaneCommandLog"
        case .close: return "closePane"
        }
    }
}

enum PaneHeaderChromePolicy {
    static let activeHeaderTintOpacity: CGFloat = 0.045
    static let controlsCornerRadius: CGFloat = 8
    static let controlsBackdropBorderOpacity: CGFloat = 0.08

    static func controlOpacity(isActive: Bool, isHovering: Bool) -> CGFloat {
        if isHovering { return 0.94 }
        return isActive ? 0.70 : 0.26
    }

    static func controlsBackdropOpacity(isActive: Bool, isHovering: Bool) -> CGFloat {
        if isHovering { return 0.12 }
        return isActive ? 0.055 : 0
    }
}

struct PaneHeaderControlLayout: Equatable {
    let buttonFrames: [NSRect]
    let buttonSize: CGFloat
    let spacing: CGFloat
    let trailingInset: CGFloat

    var controlsFrame: NSRect {
        buttonFrames.reduce(NSRect.null) { partial, frame in
            partial.union(frame)
        }
    }

    static func layout(headerWidth: CGFloat, controlCount: Int) -> PaneHeaderControlLayout {
        guard controlCount > 0, headerWidth > 0 else {
            return PaneHeaderControlLayout(buttonFrames: [], buttonSize: 0, spacing: 0, trailingInset: 0)
        }

        let desiredButton: CGFloat = 20
        let desiredSpacing: CGFloat = 3
        let desiredInset: CGFloat = 8
        let minButton: CGFloat = 9
        let minSpacing: CGFloat = 1
        let minInset: CGFloat = 2
        let count = CGFloat(controlCount)

        let desiredWidth = count * desiredButton + (count - 1) * desiredSpacing + desiredInset * 2
        let buttonSize: CGFloat
        let spacing: CGFloat
        let inset: CGFloat

        if headerWidth >= desiredWidth {
            buttonSize = desiredButton
            spacing = desiredSpacing
            inset = desiredInset
        } else {
            inset = minInset
            spacing = minSpacing
            let available = max(0, headerWidth - inset * 2 - (count - 1) * spacing)
            buttonSize = max(minButton, floor(available / count))
        }

        let totalWidth = count * buttonSize + (count - 1) * spacing
        let originX = max(0, headerWidth - inset - totalWidth)
        let frames = (0..<controlCount).map { index in
            NSRect(
                x: originX + CGFloat(index) * (buttonSize + spacing),
                y: 0,
                width: buttonSize,
                height: buttonSize
            )
        }
        return PaneHeaderControlLayout(
            buttonFrames: frames,
            buttonSize: buttonSize,
            spacing: spacing,
            trailingInset: inset
        )
    }
}

struct PaneHeaderActionHoverTip: Equatable {
    let text: String
    let anchorFrame: NSRect
}

enum PaneHeaderHoverTipPresentation {
    static let delay: TimeInterval = 0.24
    static let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)

    private static let horizontalPadding: CGFloat = 7
    private static let verticalPadding: CGFloat = 3
    private static let verticalGap: CGFloat = 6
    private static let edgeMargin: CGFloat = 4

    static func label(for action: PaneContextAction?) -> String {
        guard let action else { return L("更多操作") }
        return PaneHeaderActionPresentation.title(for: action)
    }

    static func label(for action: PaneContextAction?, shortcut: String?) -> String {
        let base = label(for: action)
        guard let shortcut,
              !shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return base
        }
        return base + "  " + ShortcutSymbolizer.symbolize(shortcut)
    }

    static func frame(for text: String, anchoredAt anchor: NSRect, in bounds: NSRect) -> NSRect {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let availableWidth = max(1, bounds.width - edgeMargin * 2)
        let width = min(ceil(textSize.width + horizontalPadding * 2), availableWidth)
        let height = ceil(textSize.height + verticalPadding * 2)
        let minX = bounds.minX + edgeMargin
        let maxX = max(minX, bounds.maxX - edgeMargin - width)
        let preferredX = anchor.midX - width / 2
        let x = min(max(preferredX, minX), maxX)
        let y = anchor.maxY + verticalGap
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class PaneHeaderHoverTipPresenter {
    private let tipView = PaneHeaderHoverTipView()
    private let panel: NSPanel
    private weak var parentWindow: NSWindow?
    private var visibleTip: PaneHeaderActionHoverTip?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = tipView
    }

    func show(_ tip: PaneHeaderActionHoverTip, from hostView: NSView) {
        guard let hostWindow = hostView.window else { return }
        visibleTip = tip
        tipView.text = tip.text

        let anchorInWindow = hostView.convert(tip.anchorFrame, to: nil)
        let anchorOnScreen = hostWindow.convertToScreen(anchorInWindow)
        let screenBounds = hostWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? hostWindow.frame
        var frame = PaneHeaderHoverTipPresentation.frame(
            for: tip.text,
            anchoredAt: anchorOnScreen,
            in: screenBounds
        )
        frame.origin.y = min(frame.origin.y, screenBounds.maxY - frame.height - 4)
        frame.origin.y = max(frame.origin.y, screenBounds.minY + 4)

        if parentWindow !== hostWindow {
            parentWindow?.removeChildWindow(panel)
            hostWindow.addChildWindow(panel, ordered: .above)
            parentWindow = hostWindow
        }
        tipView.frame = NSRect(origin: .zero, size: frame.size)
        tipView.isHidden = false
        panel.setFrame(frame, display: false)

        guard !panel.isVisible else {
            panel.alphaValue = 1
            panel.orderFront(nil)
            return
        }
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFront(nil)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func reposition(from hostView: NSView) {
        guard let visibleTip else { return }
        show(visibleTip, from: hostView)
    }

    func hide() {
        visibleTip = nil
        guard panel.isVisible else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            tipView.isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, visibleTip == nil else { return }
                panel.orderOut(nil)
                tipView.isHidden = true
            }
        })
    }
}

@MainActor
final class PaneHeaderActionStrip: NSView {
    var onAction: ((PaneContextAction) -> Void)?
    var onMore: ((PaneHeaderButton) -> Void)?
    var onHoverTip: ((PaneHeaderActionHoverTip?) -> Void)?
    var shortcutProvider: ((PaneContextAction) -> String?)?

    var isPaneActive = false { didSet { updateChrome() } }
    var isHeaderHovering = false { didSet { updateChrome() } }

    var buttonCount: Int { buttons.count }

    private var buttons: [PaneHeaderButton] = []
    private weak var hoveredButton: PaneHeaderButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = PaneHeaderChromePolicy.controlsCornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        setupButtons()
        updateChrome()
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyLayout(_ layout: PaneHeaderControlLayout) {
        let controlsFrame = layout.controlsFrame
        for (button, frame) in zip(buttons, layout.buttonFrames) {
            button.frame = frame.offsetBy(dx: -controlsFrame.minX, dy: 0)
            button.symbolPointSize = max(8, frame.width - 6)
        }
        if let hoveredButton {
            emitHoverTip(for: hoveredButton)
        }
    }

    func dismissHoverTip() {
        hoveredButton = nil
        onHoverTip?(nil)
    }

    private func setupButtons() {
        for action in PaneHeaderActionPresentation.primaryActions {
            let button = PaneHeaderButton(
                symbolName: PaneHeaderActionPresentation.systemImage(for: action),
                label: PaneHeaderHoverTipPresentation.label(for: action),
                action: action
            )
            button.onPress = { [weak self] in
                self?.dismissHoverTip()
                self?.onAction?(action)
            }
            wireHover(for: button)
            addSubview(button)
            buttons.append(button)
        }

        let moreButton = PaneHeaderButton(
            symbolName: "ellipsis",
            label: PaneHeaderHoverTipPresentation.label(for: nil),
            action: nil
        )
        moreButton.onPress = { [weak self, weak moreButton] in
            guard let self, let moreButton else { return }
            dismissHoverTip()
            onMore?(moreButton)
        }
        wireHover(for: moreButton)
        addSubview(moreButton)
        buttons.append(moreButton)
    }

    private func wireHover(for button: PaneHeaderButton) {
        button.onPressStart = { [weak self] in self?.dismissHoverTip() }
        button.onHoverChange = { [weak self, weak button] isHovering in
            guard let self, let button else { return }
            if isHovering {
                hoveredButton = button
                emitHoverTip(for: button)
            } else if hoveredButton === button {
                hoveredButton = nil
                onHoverTip?(nil)
            }
        }
    }

    private func emitHoverTip(for button: PaneHeaderButton) {
        guard let superview else { return }
        let anchor = button.convert(button.bounds, to: superview)
        let shortcut = button.paneAction.flatMap { shortcutProvider?($0) }
        let text = PaneHeaderHoverTipPresentation.label(for: button.paneAction, shortcut: shortcut)
        onHoverTip?(PaneHeaderActionHoverTip(text: text, anchorFrame: anchor))
    }

    private func updateChrome() {
        alphaValue = PaneHeaderChromePolicy.controlOpacity(isActive: isPaneActive, isHovering: isHeaderHovering)
        layer?.backgroundColor = NSColor(AppStyle.hoverFill)
            .withAlphaComponent(PaneHeaderChromePolicy.controlsBackdropOpacity(isActive: isPaneActive, isHovering: isHeaderHovering))
            .cgColor
        layer?.borderColor = NSColor(AppStyle.textPrimary)
            .withAlphaComponent((isPaneActive || isHeaderHovering) ? PaneHeaderChromePolicy.controlsBackdropBorderOpacity : 0)
            .cgColor
        for button in buttons {
            button.isPaneActive = isPaneActive
        }
    }
}

@MainActor
final class PaneHeaderButton: NSView {
    let paneAction: PaneContextAction?
    let hoverTipLabel: String
    var onPress: (() -> Void)?
    var onPressStart: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var isPaneActive = false { didSet { updateAppearance() } }
    var symbolPointSize: CGFloat = 14 { didSet { updateSymbol() } }
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            updateAppearance()
            onHoverChange?(hovering)
        }
    }
    private var pressing = false { didSet { updateAppearance() } }
    private var trackingArea: NSTrackingArea?
    private let symbolName: String
    private let imageView = NSImageView()

    init(symbolName: String, label: String, action: PaneContextAction?) {
        self.symbolName = symbolName
        self.hoverTipLabel = label
        self.paneAction = action
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        toolTip = label
        setAccessibilityLabel(label)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        updateSymbol()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }

    override func layout() {
        super.layout()
        let inset = max(2, floor(bounds.width * 0.18))
        imageView.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func mouseDown(with event: NSEvent) {
        pressing = true
        onPressStart?()
        animateScale(0.86)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldFire = bounds.contains(point)
        clearInteractionState()
        animateScale(1)
        if shouldFire { onPress?() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clearInteractionState() }
    }

    private func clearInteractionState() {
        pressing = false
        hovering = false
    }

    private func updateAppearance() {
        let activeOpacity = isPaneActive ? 0.88 : 0.74
        imageView.contentTintColor = NSColor(isPaneActive ? AppStyle.textSecondary : AppStyle.textTertiary)
            .withAlphaComponent(hovering ? 0.95 : activeOpacity)
        layer?.backgroundColor = (hovering || pressing)
            ? NSColor(AppStyle.hoverFill).cgColor
            : NSColor.clear.cgColor
    }

    private func updateSymbol() {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: hoverTipLabel)?
            .withSymbolConfiguration(config)
        needsLayout = true
    }

    private func animateScale(_ scale: CGFloat) {
        guard let layer else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = scale == 1 ? 0.16 : 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}

@MainActor
final class PaneHeaderHoverTipView: NSView {
    var text: String = "" {
        didSet {
            label.stringValue = text
            needsLayout = true
        }
    }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = AppStyle.cardBackground.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(AppStyle.textPrimary).withAlphaComponent(0.12).cgColor
        alphaValue = 0
        isHidden = true
        setAccessibilityElement(false)

        label.font = PaneHeaderHoverTipPresentation.font
        label.textColor = NSColor(AppStyle.textSecondary)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 7, dy: 3)
    }
}
