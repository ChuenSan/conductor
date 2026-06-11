import ConductorCore
import SwiftUI

/// 状态栏「等你回复」chip：agent 卡在权限确认/提问的数量（琥珀）。
/// 点击弹出收件箱，可不切 pane 直接快捷回复。没有阻塞时整个 chip 隐身。
struct BlockedInboxChip: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        if !coordinator.blockedPanes.isEmpty {
            Button { showing.toggle() } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("\(coordinator.blockedPanes.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(AppStyle.waitAmber)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(hovering ? AppStyle.activeFill : AppStyle.hoverFill))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(L("%ld 个 Agent 在等你回复，点击处理", coordinator.blockedPanes.count))
            .popover(isPresented: $showing, arrowEdge: .top) {
                BlockedInboxView(coordinator: coordinator) { showing = false }
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

/// 「等你回复」收件箱：每行一个被卡住的 agent pane，
/// 提供 ⏎/1/2/3/Esc 快捷键与自由文本回复（直接打进对应终端，不切 pane）。
struct BlockedInboxView: View {
    @ObservedObject var coordinator: AppCoordinator
    let onClose: () -> Void

    private var items: [(pane: PaneID, info: BlockedPaneInfo)] {
        coordinator.blockedPanes
            .map { (pane: $0.key, info: $0.value) }
            .sorted { $0.info.since < $1.info.since }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.waitAmber)
                Text(L("等你回复"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                Text(L("回复后自动出列"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle().fill(AppStyle.separator).frame(height: 1)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items, id: \.pane) { item in
                        BlockedRow(
                            title: coordinator.paneTitles[item.pane] ?? L("终端"),
                            agentID: coordinator.paneAgents[item.pane],
                            info: item.info,
                            onQuickKey: { key in coordinator.sendQuickKey(key, to: item.pane) },
                            onReply: { text in coordinator.sendQuickReply(text, to: item.pane) },
                            onJump: {
                                onClose()
                                coordinator.revealPane(item.pane)
                            }
                        )
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 360)
        }
        .frame(width: 340)
        .background(AppStyle.windowBackground)
    }
}

private struct BlockedRow: View {
    let title: String
    let agentID: String?
    let info: BlockedPaneInfo
    let onQuickKey: (String) -> Void
    let onReply: (String) -> Void
    let onJump: () -> Void

    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let agentID, let image = CLIToolLogo.image(named: agentID) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.waitAmber)
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onJump) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L("跳过去"))
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(AppStyle.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("切到该终端处理"))
            }
            Text(info.message)
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // 快捷按键：⏎ 默认确认；1/2/3 对应 TUI 选项；Esc 取消
            HStack(spacing: 4) {
                quickKey("⏎", L("发送回车（默认确认）"), "enter")
                quickKey("1", L("选第 1 项"), "1")
                quickKey("2", L("选第 2 项"), "2")
                quickKey("3", L("选第 3 项"), "3")
                quickKey("Esc", L("发送 Esc（取消）"), "esc")
                TextField(L("回复并回车…"), text: $reply)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AppStyle.activeFill))
                    .onSubmit {
                        let text = reply
                        reply = ""
                        onReply(text)
                    }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppStyle.hoverFill))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AppStyle.waitAmber.opacity(0.35), lineWidth: 1))
    }

    private func quickKey(_ label: String, _ help: String, _ key: String) -> some View {
        Button { onQuickKey(key) } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppStyle.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 21)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppStyle.activeFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
