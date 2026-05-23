import ConductorCore
import Combine
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct NotificationPanelSnapshot: Equatable {
    let chromeClarity: ChromeClarity
    let rows: [NotificationPanelRowSnapshot]
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
        self.unreadCount = unreadCount
        self.recordCount = recordCount
        self.canJumpToLatestUnread = canJumpToLatestUnread
        self.canClearNotifications = canClearNotifications
    }

    @MainActor
    init(model: ConductorWindowModel) {
        let notificationState = model.notifications
        let terminalTitles = Self.terminalTitlesByID(workspaces: model.workspaces)
        self.init(
            chromeClarity: model.appearance.chromeClarity,
            rows: notificationState.records.enumerated().map { index, notification in
                NotificationPanelRowSnapshot(
                    notification: notification,
                    terminalTitle: terminalTitles[notification.terminalID] ?? L("终端", "Terminal"),
                    presentationIndex: index
                )
            },
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
        ConductorGlassSurface(style: .panel, clarity: snapshot.chromeClarity, interactive: true) {
            VStack(alignment: .leading, spacing: 0) {
                notificationHeader

                Rectangle()
                    .fill(theme.floatingSeparator)
                    .frame(height: 1)

                if snapshot.isEmpty {
                    emptyNotifications
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
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
                        .padding(8)
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
        .animation(ConductorMotion.list(itemCount: snapshot.rows.count), value: snapshot.rows.map(\.id))
        .animation(ConductorMotion.attention, value: snapshot.unreadCount)
    }

    private var notificationHeader: some View {
        FloatingPanelHeader(
            systemImage: snapshot.headerSystemImage,
            title: L("通知", "Notifications"),
            subtitle: snapshot.subtitle,
            closeHelp: L("关闭通知", "Close Notifications")
        ) {
            onClose()
        } trailing: {
            Button(L("跳转", "Jump")) {
                ConductorMotion.perform(ConductorMotion.selection) {
                    onJumpToLatestUnread()
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .foregroundStyle(snapshot.canJumpToLatestUnread ? theme.floatingEmphasis : ConductorDesign.tertiaryText)
            .disabled(!snapshot.canJumpToLatestUnread)

            Button(L("清空", "Clear")) {
                ConductorMotion.perform(ConductorMotion.list) {
                    onClearAll()
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .foregroundStyle(snapshot.canClearNotifications ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
            .disabled(!snapshot.canClearNotifications)
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var emptyNotifications: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.conductorSystem(size: 21, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text(L("暂无通知", "No notifications"))
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
            Text(L("终端通知、响铃和任务完成都会出现在这里", "Terminal notifications, bells, and task completions appear here"))
                .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                ConductorMotion.perform(ConductorMotion.emphasized) {
                    onTestNotification()
                }
            } label: {
                Label(L("发送测试通知", "Send Test Notification"), systemImage: "bell.badge")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(theme.floatingControlStrongFill)
                    .clipShape(Capsule())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
        HStack(alignment: .top, spacing: 7) {
            Button {
                onOpen()
            } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: iconName)
                        .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(iconColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(theme.floatingControlFill)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(theme.floatingStroke, lineWidth: 1)
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
                    .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                    .foregroundStyle(hovering ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
                    .frame(width: 18, height: 18)
                    .background(hovering ? theme.floatingControlFill : theme.floatingControlFill.opacity(0.40))
                    .clipShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .macNativeTooltip(L("清除通知", "Clear Notification"))
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    row.unread ? theme.floatingSelectedStroke : theme.floatingStroke,
                    lineWidth: 1
                )
        }
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.attention, value: row.unread)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
    }

    private var rowTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(notification.title)
                .font(.conductorSystem(size: 11.5, weight: row.unread ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var rowBody: some View {
        if !notification.body.isEmpty {
            Text(notification.body)
                .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowMetadata: some View {
        HStack(spacing: 5) {
            Label(kindLabel, systemImage: kindChipIcon)
                .font(.conductorSystem(size: 9, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(theme.floatingControlFill.opacity(0.58))
                .clipShape(Capsule())

            Label(row.terminalTitle, systemImage: "terminal")
                .font(.conductorSystem(size: 9, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(theme.floatingControlFill)
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
    }

    private var rowBackground: some View {
        LinearGradient(
            colors: [
                hovering ? theme.floatingControlStrongFill : (row.unread ? theme.floatingSelectedFill : theme.floatingControlFill),
                row.unread ? theme.floatingHoverFill : theme.floatingControlFill.opacity(0.35),
                Color.black.opacity(0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
