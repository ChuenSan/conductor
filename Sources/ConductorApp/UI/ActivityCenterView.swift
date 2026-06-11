import SwiftUI

/// 状态栏铃铛：有未读时亮 accent 并带角标，点击弹出最近完成列表。
struct ActivityBellView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var log: AgentActivityLog
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
            if showing { log.markSeen() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: log.unseenCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(log.unseenCount > 0 ? AppStyle.accent : AppStyle.textTertiary)
                    .symbolRenderingMode(.hierarchical)
                if log.unseenCount > 0 {
                    Text("\(log.unseenCount)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(height: 13)
                        .background(Capsule().fill(AppStyle.accent))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Agent 完成记录"))
        .popover(isPresented: $showing, arrowEdge: .top) {
            ActivityCenterView(coordinator: coordinator, log: log) { showing = false }
        }
    }
}

/// 通知中心：最近完成的 agent 任务列表，点击条目跳到对应 pane。
struct ActivityCenterView: View {
    let coordinator: AppCoordinator
    @ObservedObject var log: AgentActivityLog
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Agent 完成记录"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                if !log.entries.isEmpty {
                    Button(L("清空")) { log.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle().fill(AppStyle.separator).frame(height: 1)

            if log.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(AppStyle.textTertiary)
                    Text(L("还没有完成记录。Agent 跑完任务会记在这里。"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(log.entries) { entry in
                            ActivityRow(entry: entry, coordinator: coordinator) {
                                onClose()
                                if let pane = entry.paneID {
                                    coordinator.focusPane(byID: pane.value)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
        .background(AppStyle.windowBackground)
    }
}

private struct ActivityRow: View {
    let entry: AgentActivityEntry
    let coordinator: AppCoordinator
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 9) {
                logo
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(AppStyle.textTertiary)
                    }
                    if !entry.message.isEmpty {
                        Text(entry.message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppStyle.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? AppStyle.hoverFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.paneID != nil ? L("点击跳到该终端") : "")
    }

    @ViewBuilder
    private var logo: some View {
        if let agentID = entry.agentID, let image = CLIToolLogo.image(named: agentID) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: 15, height: 15)
                .padding(.top, 1)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppStyle.accent)
                .padding(.top, 1)
        }
    }
}
