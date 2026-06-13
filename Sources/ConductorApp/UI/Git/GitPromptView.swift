import ConductorGit
import SwiftUI

/// 居中弹出的对话框：输入（新建分支/标签、重命名、设上游、stash→分支）、
/// reset 模式三选、危险操作确认。由 `model.prompt` 驱动。
struct GitPromptView: View {
    @ObservedObject var model: GitPanelModel
    let prompt: GitPrompt
    @State private var text: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { model.prompt = nil }
            card
                .frame(width: 320)
        }
        .onAppear { text = initialText }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)

            switch prompt {
            case .resetMode:
                resetModeBody
            case .confirmDeleteBranch, .confirmDeleteTag, .confirmDropStash:
                confirmBody
            default:
                textBody
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppStyle.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppStyle.separator))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
    }

    // MARK: 文本输入

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sub = subtitle {
                Text(sub).font(.system(size: 11)).foregroundStyle(AppStyle.textTertiary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { model.submitPrompt(text) }
            buttons(confirmLabel: L("确定"), destructive: false) {
                model.submitPrompt(text)
            }
        }
    }

    // MARK: reset 模式

    private var resetModeBody: some View {
        guard case let .resetMode(commit) = prompt else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(L("重置到 %@", commit.shortSHA))
                .font(.system(size: 11)).foregroundStyle(AppStyle.textTertiary)
            resetOption(.soft, L("Soft — 保留改动并暂存"))
            resetOption(.mixed, L("Mixed — 保留改动不暂存"))
            resetOption(.hard, L("Hard — 丢弃所有改动"), destructive: true)
            HStack {
                Spacer()
                Button(L("取消")) { model.prompt = nil }.buttonStyle(.plain)
                    .foregroundStyle(AppStyle.textSecondary)
            }
        })
    }

    private func resetOption(_ mode: GitResetMode, _ label: String, destructive: Bool = false) -> some View {
        Button {
            if case let .resetMode(commit) = prompt { model.resetTo(commit, mode: mode) }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? AppStyle.errorRed : AppStyle.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: 确认

    private var confirmBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(confirmMessage).font(.system(size: 12)).foregroundStyle(AppStyle.textSecondary)
            buttons(confirmLabel: confirmLabel, destructive: true) {
                switch prompt {
                case let .confirmDeleteBranch(b): model.deleteBranch(b, force: true)
                case let .confirmDeleteTag(t): model.deleteTag(t)
                case let .confirmDropStash(s): model.dropStash(s)
                default: model.prompt = nil
                }
            }
        }
    }

    // MARK: 通用按钮行

    private func buttons(confirmLabel: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(L("取消")) { model.prompt = nil }
                .buttonStyle(.plain)
                .foregroundStyle(AppStyle.textSecondary)
            Button(action: action) {
                Text(confirmLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(destructive ? AppStyle.errorRed : AppStyle.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressScaleStyle())
        }
    }

    // MARK: 文案

    private var title: String {
        switch prompt {
        case .createBranch: L("新建分支")
        case .createTag: L("新建标签")
        case .renameBranch: L("重命名分支")
        case .setUpstream: L("设置上游分支")
        case .stashToBranch: L("从贮藏新建分支")
        case .resetMode: L("重置当前分支")
        case .confirmDeleteBranch: L("删除分支")
        case .confirmDeleteTag: L("删除标签")
        case .confirmDropStash: L("丢弃贮藏")
        }
    }

    private var subtitle: String? {
        switch prompt {
        case let .createBranch(_, base): L("基于 %@", base)
        case let .createTag(_, base): L("基于 %@", base)
        default: nil
        }
    }

    private var placeholder: String {
        switch prompt {
        case .createBranch, .renameBranch, .stashToBranch: L("分支名")
        case .createTag: L("标签名")
        case .setUpstream: L("上游，如 origin/main")
        default: ""
        }
    }

    private var initialText: String {
        switch prompt {
        case let .renameBranch(b): b.name
        case let .setUpstream(b): "origin/\(b.name)"
        default: ""
        }
    }

    private var confirmLabel: String {
        if case .confirmDropStash = prompt { return L("丢弃") }
        return L("删除")
    }

    private var confirmMessage: String {
        switch prompt {
        case let .confirmDeleteBranch(b): L("确定删除分支 %@？此操作不可撤销。", b.friendlyName)
        case let .confirmDeleteTag(t): L("确定删除标签 %@？", t.name)
        case let .confirmDropStash(s): L("确定丢弃贮藏 %@？", s.message)
        default: ""
        }
    }
}
