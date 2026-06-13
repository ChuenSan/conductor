import ConductorGit
import SwiftUI

/// 选中文件的 diff 查看器（叠在变更段之上）。行号栏 + 增删着色，等宽字体。
struct GitDiffView: View {
    @ObservedObject var model: GitPanelModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppStyle.separator)
            body(for: model.diff)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { model.selection = nil }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
            }
            .buttonStyle(IconButtonStyle(size: 24))
            .help(L("返回"))

            if let path = model.selection?.path {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let diff = model.diff, !diff.isBinary {
                Text("+\(diff.addedCount)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AppStyle.doneGreen)
                Text("−\(diff.deletedCount)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AppStyle.errorRed)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func body(for diff: TextDiff?) -> some View {
        if model.diffLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff, diff.isBinary {
            message(L("二进制文件，无法显示差异"))
        } else if let diff, !diff.isEmpty {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                        hunkHeaderRow(hunk)
                        ForEach(hunk.lines) { line in
                            GitDiffLineRow(line: line)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        } else {
            message(L("没有差异"))
        }
    }

    @ViewBuilder
    private func hunkHeaderRow(_ hunk: TextDiffHunk) -> some View {
        HStack(spacing: 6) {
            Text(hunk.header)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(AppStyle.accent)
                .lineLimit(1)
            Spacer(minLength: 8)
            hunkAction(for: hunk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.accent.opacity(0.08))
    }

    /// 逐 hunk 暂存/取消暂存按钮（按当前 diff 来源决定方向；未跟踪文件不显示）。
    @ViewBuilder
    private func hunkAction(for hunk: TextDiffHunk) -> some View {
        switch model.selection?.source {
        case .workTree:
            hunkButton(L("暂存此块"), "plus") { model.stageHunk(hunk) }
        case .staged:
            hunkButton(L("取消暂存此块"), "minus") { model.unstageHunk(hunk) }
        default:
            EmptyView()
        }
    }

    private func hunkButton(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
                Text(title).font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(AppStyle.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(AppStyle.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(AppStyle.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// diff 的一行：左侧旧/新行号栏 + 着色内容。
private struct GitDiffLineRow: View {
    let line: TextDiffLine

    var body: some View {
        HStack(spacing: 0) {
            lineNumber(line.oldLine)
            lineNumber(line.newLine)
            Text(prefix + line.content)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(textColor)
                .padding(.leading, 6)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private func lineNumber(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppStyle.textTertiary.opacity(0.7))
            .frame(width: 34, alignment: .trailing)
            .padding(.trailing, 4)
    }

    private var prefix: String {
        switch line.kind {
        case .added: "+"
        case .deleted: "-"
        case .noNewline: ""
        case .context: " "
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added: AppStyle.doneGreen
        case .deleted: AppStyle.errorRed
        case .noNewline: AppStyle.textTertiary
        case .context: AppStyle.textSecondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: AppStyle.doneGreen.opacity(0.10)
        case .deleted: AppStyle.errorRed.opacity(0.10)
        default: Color.clear
        }
    }
}
