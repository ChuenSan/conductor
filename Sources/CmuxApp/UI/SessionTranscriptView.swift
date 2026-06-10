import CmuxCore
import SwiftUI

/// 虚拟滚动 transcript：LazyVStack 只渲染可见行，适合长会话全量浏览。
struct SessionTranscriptView: View {
    let messages: [AgentSessionMessage]
    var maxHeight: CGFloat? = nil
    var fontSize: CGFloat = 11

    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(messages) { message in
                    SessionMessageBubble(message: message, fontSize: fontSize)
                        .id(message.id)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: maxHeight)
    }
}

struct SessionMessageBubble: View {
    let message: AgentSessionMessage
    var fontSize: CGFloat = 11

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(message.role == .user ? "我" : "AI")
                .font(.system(size: fontSize - 2, weight: .bold))
                .foregroundStyle(message.role == .user ? AppStyle.accent : AppStyle.textSecondary)
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(message.role == .user
                            ? AppStyle.accent.opacity(0.12)
                            : AppStyle.hoverFill))
            Text(message.text)
                .font(.system(size: fontSize))
                .foregroundStyle(message.role == .user ? AppStyle.textPrimary : AppStyle.textSecondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
