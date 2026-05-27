import ConductorCore
import Combine
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct NotificationPanelSnapshot: Equatable {
    let chromeClarity: ChromeClarity
    let rows: [NotificationPanelRowSnapshot]
    let rowIDs: [UUID]
    let unreadCount: Int
    let recordCount: Int
    let canJumpToLatestUnread: Bool
    let canClearNotifications: Bool

    init(
        chromeClarity: ChromeClarity,
        rows: [NotificationPanelRowSnapshot],
        unreadCount: Int,
        recordCount: Int,
        canJumpToLatestUnread: Bool,
        canClearNotifications: Bool
    ) {
        self.chromeClarity = chromeClarity
        self.rows = rows
        self.rowIDs = rows.map(\.id)
        self.unreadCount = unreadCount
        self.recordCount = recordCount
        self.canJumpToLatestUnread = canJumpToLatestUnread
        self.canClearNotifications = canClearNotifications
    }

    @MainActor
    init(model: ConductorWindowModel) {
        let notificationState = model.notifications
        let terminalTitles = Self.terminalTitlesByID(workspaces: model.workspaces)
        let rows = notificationState.records.enumerated().map { index, notification in
            NotificationPanelRowSnapshot(
                notification: notification,
                terminalTitle: terminalTitles[notification.terminalID] ?? L("终端", "Terminal"),
                presentationIndex: index
            )
        }
        self.init(
            chromeClarity: model.appearance.chromeClarity,
            rows: rows,
            unreadCount: notificationState.snapshot.unreadCount,
            recordCount: notificationState.records.count,
            canJumpToLatestUnread: model.canPerformCommand(.jumpToLatestUnread),
            canClearNotifications: model.canPerformCommand(.clearNotifications)
        )
    }

    var isEmpty: Bool {
        rows.isEmpty
    }

    var headerSystemImage: String {
        unreadCount > 0 ? "bell.badge.fill" : "bell"
    }

    var subtitle: String {
        isEmpty ? L("暂无通知", "No notifications") : L("\(recordCount) 条记录", "\(recordCount) records")
    }

    private static func terminalTitlesByID(workspaces: [WorkspaceState]) -> [TerminalID: String] {
        var titles: [TerminalID: String] = [:]
        for workspace in workspaces {
            for pane in workspace.panes.values {
                for tab in pane.tabs where titles[tab.id] == nil {
                    titles[tab.id] = tab.title
                }
            }
        }
        return titles
    }
}

struct NotificationPanelRowSnapshot: Identifiable, Equatable {
    let notification: TerminalNotificationRecord
    let terminalTitle: String
    let presentationIndex: Int

    var id: UUID {
        notification.id
    }

    var unread: Bool {
        !notification.isRead
    }
}

struct NotificationPanelRootView: View {
    @StateObject private var store: NotificationPanelStore

    init(model: ConductorWindowModel) {
        _store = StateObject(wrappedValue: NotificationPanelStore(model: model))
    }

    var body: some View {
        NotificationPanelView(
            snapshot: store.snapshot,
            onClose: store.close,
            onJumpToLatestUnread: store.jumpToLatestUnread,
            onClearAll: store.clearAll,
            onOpen: store.open,
            onClear: store.clear,
            onTestNotification: store.testNotification
        )
            .environment(\.colorScheme, store.theme.chromeColorScheme)
            .preferredColorScheme(store.theme.chromeColorScheme)
            .environment(\.conductorTheme, store.theme)
            .environment(\.conductorFontScale, store.appearance.fontScale)
            .environment(\.conductorFontFamily, store.appearance.fontFamily)
            .environment(\.locale, store.appearance.language.locale)
    }
}

@MainActor
private final class NotificationPanelStore: ObservableObject {
    let model: ConductorWindowModel
    @Published private(set) var snapshot: NotificationPanelSnapshot
    @Published private(set) var theme: TerminalTheme
    @Published private(set) var appearance: AppearancePreferences

    private var cancellables = Set<AnyCancellable>()

    init(model: ConductorWindowModel) {
        self.model = model
        self.snapshot = NotificationPanelSnapshot(model: model)
        self.theme = model.theme
        self.appearance = model.appearance
        bind()
    }

    func close() {
        model.hideNotificationPanel()
    }

    func jumpToLatestUnread() {
        model.performCommand(.jumpToLatestUnread)
    }

    func clearAll() {
        model.performCommand(.clearNotifications)
    }

    func open(_ id: UUID) {
        _ = model.openNotification(id)
    }

    func clear(_ id: UUID) {
        model.clearNotification(id)
    }

    func testNotification() {
        model.performCommand(.testNotification)
    }

    private func bind() {
        model.$theme
            .removeDuplicates()
            .sink { [weak self] theme in
                guard let self, self.theme != theme else { return }
                self.theme = theme
            }
            .store(in: &cancellables)

        model.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                guard let self else { return }
                if self.appearance != appearance {
                    self.appearance = appearance
                }
                self.refreshSnapshot()
            }
            .store(in: &cancellables)

        model.$notifications
            .removeDuplicates()
            .combineLatest(model.$workspaces.removeDuplicates())
            .sink { [weak self] _, _ in
                self?.refreshSnapshot()
            }
            .store(in: &cancellables)
    }

    private func refreshSnapshot() {
        let next = NotificationPanelSnapshot(model: model)
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct NotificationPanelView: View {
    let snapshot: NotificationPanelSnapshot
    let onClose: () -> Void
    let onJumpToLatestUnread: () -> Void
    let onClearAll: () -> Void
    let onOpen: (UUID) -> Void
    let onClear: (UUID) -> Void
    let onTestNotification: () -> Void

    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    init(
        snapshot: NotificationPanelSnapshot,
        onClose: @escaping () -> Void,
        onJumpToLatestUnread: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onOpen: @escaping (UUID) -> Void,
        onClear: @escaping (UUID) -> Void,
        onTestNotification: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.onClose = onClose
        self.onJumpToLatestUnread = onJumpToLatestUnread
        self.onClearAll = onClearAll
        self.onOpen = onOpen
        self.onClear = onClear
        self.onTestNotification = onTestNotification
    }

    init(model: ConductorWindowModel) {
        self.init(
            snapshot: NotificationPanelSnapshot(model: model),
            onClose: {
                model.hideNotificationPanel()
            },
            onJumpToLatestUnread: {
                model.performCommand(.jumpToLatestUnread)
            },
            onClearAll: {
                model.performCommand(.clearNotifications)
            },
            onOpen: { id in
                _ = model.openNotification(id)
            },
            onClear: { id in
                model.clearNotification(id)
            },
            onTestNotification: {
                model.performCommand(.testNotification)
            }
        )
    }

    var body: some View {
        ConductorGlassSurface(style: .palette, clarity: snapshot.chromeClarity, interactive: true) {
            VStack(alignment: .leading, spacing: 0) {
                notificationHeader

                Rectangle()
                    .fill(theme.floatingSeparator)
                    .frame(height: 1)

                if snapshot.isEmpty {
                    emptyNotifications
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(snapshot.rows) { row in
                                NotificationRowView(
                                    row: row,
                                    onOpen: {
                                        onOpen(row.id)
                                    },
                                    onClear: {
                                        onClear(row.id)
                                    }
                                )
                                .transition(ConductorMotion.notificationRowTransition(itemCount: snapshot.rows.count))
                                .conductorCascade(
                                    index: row.presentationIndex,
                                    itemCount: snapshot.rows.count,
                                    edge: .trailing,
                                    distance: 10,
                                    scale: 0.992
                                )
                            }
                        }
                        .padding(7)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
        }
        .frame(
            minWidth: ConductorTokens.Space.notificationPanelMinWidth,
            minHeight: ConductorTokens.Space.notificationPanelMinHeight
        )
        .animation(ConductorMotion.list(itemCount: snapshot.rows.count), value: snapshot.rowIDs)
        .animation(ConductorMotion.attention, value: snapshot.unreadCount)
    }

    private var notificationHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.headerSystemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.86))
                .frame(width: 22, height: 22)
                .background(theme.floatingControlFill.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(L("通知", "Notifications"))
                    .font(.conductorSystem(size: 12.6, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(snapshot.subtitle)
                    .font(.conductorSystem(size: 9.8, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            NotificationPanelToolButton(
                systemImage: "arrowshape.turn.up.right",
                help: L("跳到最新未读", "Jump to Latest Unread"),
                isEnabled: snapshot.canJumpToLatestUnread)
            {
                ConductorMotion.perform(ConductorMotion.selection) {
                    onJumpToLatestUnread()
                }
            }

            NotificationPanelToolButton(
                systemImage: "trash",
                help: L("清空通知", "Clear Notifications"),
                isEnabled: snapshot.canClearNotifications)
            {
                ConductorMotion.perform(ConductorMotion.list) {
                    onClearAll()
                }
            }

            NotificationPanelToolButton(
                systemImage: "xmark",
                help: L("关闭通知", "Close Notifications"),
                isEnabled: true,
                action: onClose)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    private var emptyNotifications: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bell.slash")
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .frame(width: 22, height: 22)
                    .background(theme.floatingControlFill.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("暂无通知", "No notifications"))
                        .font(.conductorSystem(size: 11.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                    Text(L("终端通知、响铃和任务完成会按时间出现在这里。", "Terminal notifications, bells, and task completions appear here in time order."))
                        .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                ConductorMotion.perform(ConductorMotion.emphasized) {
                    onTestNotification()
                }
            } label: {
                Label(L("发送测试通知", "Send Test Notification"), systemImage: "bell.badge")
                    .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(theme.floatingControlFill.opacity(0.64))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(ConductorPressButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(.opacity)
    }
}

private struct NotificationPanelToolButton: View {
    let systemImage: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.6, weight: .semibold, scale: fontScale))
                .foregroundStyle(isEnabled ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
                .frame(width: 23, height: 23)
                .background(theme.floatingControlFill.opacity(isEnabled ? 0.58 : 0.28))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .disabled(!isEnabled)
        .accessibilityLabel(help)
        .macNativeTooltip(help)
    }
}

private struct NotificationRowView: View {
    let row: NotificationPanelRowSnapshot
    let onOpen: () -> Void
    let onClear: () -> Void

    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    private var notification: TerminalNotificationRecord {
        row.notification
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                onOpen()
            } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: iconName)
                        .font(.conductorSystem(size: 9.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(iconColor)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(theme.floatingControlFill.opacity(0.34))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(theme.floatingStroke.opacity(0.30), lineWidth: 0.6)
                        }
                        .overlay(alignment: .topTrailing) {
                            if row.unread {
                                Circle()
                                    .fill(theme.floatingEmphasis)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 2, y: -2)
                                    .conductorSignalPulse(active: row.unread, trigger: row.notification.id)
                            }
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        rowTitle
                        rowBody
                        rowMetadata
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ConductorPressButtonStyle())

            Button {
                ConductorMotion.perform(ConductorMotion.list, onClear)
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(hovering ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
                    .frame(width: 18, height: 18)
                    .background(hovering ? theme.floatingControlFill.opacity(0.42) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(ConductorPressButtonStyle())
            .accessibilityLabel(L("清除通知", "Clear Notification"))
            .macNativeTooltip(L("清除通知", "Clear Notification"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    row.unread ? theme.floatingSelectedStroke.opacity(0.38) : theme.floatingStroke.opacity(0.20),
                    lineWidth: 0.6
                )
        }
        .animation(ConductorMotion.attention, value: row.unread)
        .conductorHover($hovering, animation: nil)
    }

    private var rowTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(notification.title)
                .font(.conductorSystem(size: 11.2, weight: row.unread ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var rowBody: some View {
        if !notification.body.isEmpty {
            Text(notification.body)
                .font(.conductorSystem(size: 10.1, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowMetadata: some View {
        HStack(spacing: 5) {
            Label(kindLabel, systemImage: kindChipIcon)
                .font(.conductorSystem(size: 8.8, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)

            Label(row.terminalTitle, systemImage: "terminal")
                .font(.conductorSystem(size: 8.8, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var rowBackground: Color {
        if hovering {
            return theme.floatingHoverFill.opacity(0.78)
        }
        if row.unread {
            return theme.floatingSelectedFill.opacity(0.72)
        }
        return theme.floatingControlFill.opacity(0.34)
    }

    private var iconName: String {
        switch notification.kind {
        case .agent:
            "terminal"
        case .bell:
            "bell"
        case .notification:
            "terminal"
        }
    }

    private var kindChipIcon: String {
        switch notification.kind {
        case .agent:
            "bolt.horizontal"
        case .bell:
            "bell"
        case .notification:
            "app.badge"
        }
    }

    private var kindLabel: String {
        switch notification.kind {
        case .agent:
            "Agent"
        case .bell:
            L("响铃", "Bell")
        case .notification:
            L("终端", "Terminal")
        }
    }

    private var iconColor: Color {
        switch notification.kind {
        case .agent:
            ConductorDesign.secondaryText
        case .bell:
            ConductorDesign.warmAccent
        case .notification:
            ConductorDesign.secondaryText
        }
    }
}
