import ConductorGit
import SwiftUI

/// blame / 单文件历史 的全面板叠层。由 `model.inspector` 驱动。
struct GitInspectorView: View {
    @ObservedObject var model: GitPanelModel
    let inspector: GitInspector

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppStyle.separator)
            if model.inspectorLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch inspector {
                case .blame: blameBody
                case .fileHistory: historyBody
                }
            }
        }
        .background(AppStyle.windowBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.closeInspector() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(AppStyle.textSecondary)
            }
            .buttonStyle(IconButtonStyle(size: 24))
            Image(systemName: inspector.icon).font(.system(size: 11)).foregroundStyle(AppStyle.accent)
            Text(inspector.titlePrefix + URL(fileURLWithPath: inspector.path).lastPathComponent)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var blameBody: some View {
        if let blame = model.blame, blame.isBinary {
            centered(L("二进制文件，无法追溯"))
        } else if let blame = model.blame, !blame.lines.isEmpty {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(blame.lines) { line in
                        HStack(spacing: 8) {
                            Text(line.shortSHA)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppStyle.accent).frame(width: 64, alignment: .leading)
                            Text(line.author)
                                .font(.system(size: 10)).foregroundStyle(AppStyle.textTertiary)
                                .frame(width: 90, alignment: .leading).lineLimit(1)
                            Text("\(line.lineNumber)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppStyle.textTertiary.opacity(0.7))
                                .frame(width: 34, alignment: .trailing)
                            Text(line.content)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AppStyle.textSecondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 1)
                    }
                }
                .padding(.bottom, 8)
            }
        } else {
            centered(L("无追溯信息"))
        }
    }

    @ViewBuilder
    private var historyBody: some View {
        if model.fileHistoryCommits.isEmpty {
            centered(L("该文件暂无历史"))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.fileHistoryCommits) { commit in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(commit.subject)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppStyle.textPrimary)
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(commit.author.name).font(.system(size: 10.5)).foregroundStyle(AppStyle.textSecondary)
                                Text(GitRelativeDate.string(commit.authorDate))
                                    .font(.system(size: 10.5)).foregroundStyle(AppStyle.textTertiary)
                                Spacer(minLength: 4)
                                Text(commit.shortSHA.prefix(7))
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(AppStyle.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .contextMenu { GitMenus.commit(model, commit) }
                        Divider().overlay(AppStyle.separator.opacity(0.5)).padding(.leading, 14)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func centered(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(AppStyle.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension GitInspector {
    var icon: String {
        switch self {
        case .blame: "person.crop.rectangle.stack"
        case .fileHistory: "clock.arrow.circlepath"
        }
    }

    var titlePrefix: String {
        switch self {
        case .blame: L("追溯：")
        case .fileHistory: L("历史：")
        }
    }
}
