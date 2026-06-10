import CmuxCore
import SwiftUI

/// 底部状态栏（自绘，跟主题）：当前 pane 的 cwd 全路径 + git 分支 + 实时时间。
struct StatusBarView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var usageMonitor: UsageMonitor
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        HStack(spacing: 12) {
            if let cwd = coordinator.activeCwd {
                item("folder", prettyPath(cwd))
            }
            if let branch = coordinator.activeBranch {
                item("arrow.triangle.branch", branch, accent: true)
            }
            Spacer(minLength: 8)
            CodexUsageChip(snapshot: usageMonitor.codex) { coordinator.openTools(.usage) }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 21)
        .frame(maxWidth: .infinity)
        .background(AppStyle.windowBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(AppStyle.separator).frame(height: 1)
        }
        .onAppear { usageMonitor.start() }
    }

    private func item(_ icon: String, _ text: String, accent: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(accent ? AppStyle.accent : AppStyle.textTertiary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
        }
    }

    private func prettyPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// 状态栏里的 Codex 配额小条：logo + 最紧张窗口的剩余百分比，点击打开 CLI 面板。
private struct CodexUsageChip: View {
    let snapshot: CodexUsageSnapshot?
    let onTap: () -> Void

    /// 取剩余最少（最紧张）的窗口作为头条。
    private var headline: (label: String, window: CodexUsageSnapshot.Window)? {
        guard let snapshot else { return nil }
        let candidates: [(String, CodexUsageSnapshot.Window)] =
            [("会话", snapshot.session), ("本周", snapshot.weekly)].compactMap { label, win in
                win.map { (label, $0) }
            }
        return candidates.min { $0.1.remainingPercent < $1.1.remainingPercent }
    }

    private func color(_ used: Int) -> Color {
        switch used {
        case ..<70: AppStyle.textSecondary
        case 70..<90: Color(red: 0.95, green: 0.62, blue: 0.20)
        default: Color(red: 0.92, green: 0.34, blue: 0.34)
        }
    }

    var body: some View {
        if let headline {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    if let logo = CLIToolLogo.image(named: "codex") {
                        Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 13, height: 13)
                    }
                    Text("\(headline.label) 剩 \(headline.window.remainingPercent)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color(headline.window.usedPercent))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tooltip)
        }
    }

    private var tooltip: String {
        guard let snapshot else { return "" }
        var lines: [String] = []
        if let s = snapshot.session {
            lines.append("会话：剩 \(s.remainingPercent)% · \(UsageFormatting.resetText(s.resetAt))")
        }
        if let w = snapshot.weekly {
            lines.append("本周：剩 \(w.remainingPercent)% · \(UsageFormatting.resetText(w.resetAt))")
        }
        return "Codex 用量\n" + lines.joined(separator: "\n")
    }
}
