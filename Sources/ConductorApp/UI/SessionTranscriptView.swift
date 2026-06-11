import AppKit
import ConductorCore
import SwiftUI

/// 会话 transcript 查看器，按消息量自适应两种形态：
/// - 短会话：普通 VStack，按内容自然高度（不超过 maxHeight），无虚拟化开销；
/// - 长会话：`List`（NSTableView 驱动）真·虚拟滚动，行视图随滚动回收复用，
///   并定位到最新消息（LazyVStack 只惰性创建、不回收，长会话滚一遍后内存与布局成本线性涨）。
struct SessionTranscriptView: View {
    let messages: [AgentSessionMessage]
    /// 会话所属 agent（"claude"/"codex"），AI 消息头像用对应 logo。
    var agent: String? = nil
    var maxHeight: CGFloat? = nil
    var fontSize: CGFloat = 11

    /// 超过该条数才走虚拟化（List 需要固定高度，短会话用自然高度更紧凑）。
    private static let virtualizationThreshold = 12

    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        if messages.count <= Self.virtualizationThreshold {
            compactTranscript
        } else {
            virtualizedTranscript
        }
    }

    /// 短会话：内容多高就多高，封顶 maxHeight。
    private var compactTranscript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(messages) { message in
                    SessionMessageBubble(message: message, agent: agent, fontSize: fontSize)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: maxHeight)
    }

    /// 长会话：NSTableView 行回收 + 打开即定位最新消息。
    private var virtualizedTranscript: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(messages) { message in
                    SessionMessageBubble(message: message, agent: agent, fontSize: fontSize)
                        .id(message.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            // List 没有“内容高度”概念，在外层 ScrollView 等无界容器里会塌成 0，必须给定高。
            .frame(height: maxHeight)
            .onAppear { scrollToLatest(proxy) }
            .onChange(of: messages.last?.id) { _, _ in scrollToLatest(proxy) }
        }
    }

    /// 延后一拍等 NSTableView 完成行布局，否则定位偶发落在中途。
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        DispatchQueue.main.async { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

struct SessionMessageBubble: View {
    let message: AgentSessionMessage
    /// 会话所属 agent（"claude"/"codex"），AI 头像显示对应 logo；nil 或找不到 logo 回退文字。
    var agent: String? = nil
    var fontSize: CGFloat = 11

    /// 渲染上限：预览场景不需要完整展开一条几万字的消息，超出部分截断提示。
    private static let maxRenderChars = 4000

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            avatar
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(message.role == .user
                            ? AppStyle.accent.opacity(0.12)
                            : AppStyle.hoverFill))
            Text(renderText)
                .font(.system(size: fontSize))
                .foregroundStyle(message.role == .user ? AppStyle.textPrimary : AppStyle.textSecondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 用户消息显示「我」徽标；AI 消息优先用 agent 的品牌 logo（claude/codex png），缺图回退「AI」。
    @ViewBuilder
    private var avatar: some View {
        if message.role == .user {
            Text(L("我"))
                .font(.system(size: fontSize - 2, weight: .bold))
                .foregroundStyle(AppStyle.accent)
        } else if let logo = agentLogo {
            Image(nsImage: logo)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 13, height: 13)
        } else {
            Text(L("AI"))
                .font(.system(size: fontSize - 2, weight: .bold))
                .foregroundStyle(AppStyle.textSecondary)
        }
    }

    private var agentLogo: NSImage? {
        guard let agent else { return nil }
        return CLIToolLogo.image(named: agent == "claude" ? "claude" : "codex")
    }

    private var renderText: String {
        guard message.text.count > Self.maxRenderChars else { return message.text }
        return String(message.text.prefix(Self.maxRenderChars)) + "\n" + L("…（消息过长，已截断）")
    }
}
