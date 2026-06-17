import ConductorCore
import SwiftUI

/// 审批面板（右侧）：收口所有 agent 的待批请求，就地批准/拒绝，不用跳进 pane。
struct FeedPanelView: View {
    @ObservedObject var feedCenter: FeedCenter
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L("审批"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                if !feedCenter.pending.isEmpty {
                    Text("\(feedCenter.pending.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Capsule().fill(AppStyle.accent))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("关闭"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(AppStyle.separator)

            if feedCenter.pending.isEmpty {
                ToolEmptyState(
                    icon: "checkmark.seal",
                    title: L("没有待批请求"),
                    detail: L("Agent 需要权限、退出计划或提问时，会在这里等你处理。"),
                    compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(feedCenter.pending) { request in
                            FeedRequestRow(request: request) { decision in
                                _ = withAnimation(Motion.snappy) {
                                    feedCenter.resolve(id: request.id, decision: decision)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.clear)   // 透明：用根底统一磨砂
    }
}

private struct FeedRequestRow: View {
    let request: FeedRequest
    let onDecision: (FeedDecision) -> Void

    private var actions: [FeedActionButton] { FeedPresentation.actions(for: request) }
    private var primary: [FeedActionButton] {
        actions.filter { $0.decision == .allow(.once) || $0.decision == .deny(.once) }
    }
    private var secondary: [FeedActionButton] {
        actions.filter { !($0.decision == .allow(.once) || $0.decision == .deny(.once)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                logo
                Text(FeedPresentation.title(for: request))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let category = request.category {
                    Text(category.label)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(Capsule().fill(AppStyle.hoverFill))
                }
            }

            if let body = FeedPresentation.body(for: request), !body.isEmpty {
                ScrollView {
                    Text(body)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 132)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
            }

            if !primary.isEmpty {
                HStack(spacing: 6) {
                    ForEach(primary) { button in
                        FeedDecisionButton(button: button, fullWidth: true) { onDecision(button.decision) }
                    }
                }
            }
            ForEach(secondary) { button in
                FeedDecisionButton(button: button, fullWidth: true) { onDecision(button.decision) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: AppStyle.cardBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AppStyle.separator, lineWidth: 1))
    }

    @ViewBuilder
    private var logo: some View {
        if let agent = request.agent, let image = CLIToolLogo.image(named: agent) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: 15, height: 15)
        } else {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 13))
                .foregroundStyle(AppStyle.accent)
        }
    }
}

private struct FeedDecisionButton: View {
    let button: FeedActionButton
    let fullWidth: Bool
    let action: () -> Void
    @State private var hovering = false

    /// allow-once 实心强调；其余描边。
    private var filled: Bool { button.decision == .allow(.once) }

    private var tint: Color {
        switch button.role {
        case .allow: return AppStyle.accent
        case .deny: return Color(nsColor: .systemRed)
        case .neutral: return AppStyle.textPrimary
        }
    }

    var body: some View {
        Button(action: action) {
            Text(button.label)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(filled ? Color.white : tint)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? tint : (hovering ? tint.opacity(0.12) : AppStyle.hoverFill)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(filled ? Color.clear : tint.opacity(0.35), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
