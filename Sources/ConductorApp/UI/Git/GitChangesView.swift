import ConductorGit
import SwiftUI

/// 变更段：未暂存/已暂存两个分区 + 底部提交框；选中文件时叠出 diff。
struct GitChangesView: View {
    @ObservedObject var model: GitPanelModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !model.stashes.isEmpty {
                    stashBar
                    Divider().overlay(AppStyle.separator)
                }
                if model.changes.isEmpty {
                    cleanState
                } else {
                    changesList
                }
                Divider().overlay(AppStyle.separator)
                commitBox
            }
            if model.selection != nil {
                GitDiffView(model: model)
                    .background(AppStyle.windowBackground)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: model.selection)
    }

    /// 贮藏（stash）列表，置于变更段顶部。右键应用/弹出/丢弃。
    private var stashBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
                Text(L("贮藏").uppercased())
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(AppStyle.textTertiary)
                Text("\(model.stashes.count)")
                    .font(.system(size: 9.5, weight: .bold)).foregroundStyle(AppStyle.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(AppStyle.hoverFill))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            ForEach(model.stashes) { stash in
                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 10)).foregroundStyle(AppStyle.accent)
                    Text(stash.message)
                        .font(.system(size: 11.5)).foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(GitRelativeDate.string(stash.date))
                        .font(.system(size: 9.5)).foregroundStyle(AppStyle.textTertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .contentShape(Rectangle())
                .contextMenu { GitMenus.stash(model, stash) }
            }
        }
        .padding(.bottom, 4)
    }

    private var cleanState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppStyle.doneGreen)
            Text(L("工作区干净"))
                .font(.system(size: 12.5))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var changesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !model.unstagedChanges.isEmpty {
                    Section {
                        ForEach(model.unstagedChanges) { change in
                            GitChangeRow(model: model, change: change, staged: false)
                        }
                    } header: {
                        sectionHeader(
                            title: L("变更"), count: model.unstagedChanges.count,
                            actions: [
                                .init(icon: "plus", help: L("全部暂存")) { model.stageAll() },
                            ])
                    }
                }
                if !model.stagedChanges.isEmpty {
                    Section {
                        ForEach(model.stagedChanges) { change in
                            GitChangeRow(model: model, change: change, staged: true)
                        }
                    } header: {
                        sectionHeader(
                            title: L("已暂存"), count: model.stagedChanges.count,
                            actions: [
                                .init(icon: "minus", help: L("全部取消暂存")) { model.unstageAll() },
                            ])
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private struct HeaderAction: Identifiable {
        let id = UUID()
        let icon: String
        let help: String
        let run: () -> Void
    }

    private func sectionHeader(title: String, count: Int, actions: [HeaderAction]) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
            Text("\(count)")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(AppStyle.hoverFill))
            Spacer()
            ForEach(actions) { action in
                Button(action: action.run) {
                    Image(systemName: action.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .buttonStyle(IconButtonStyle(size: 20))
                .help(action.help)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(AppStyle.windowBackground)
    }

    // MARK: - 提交框

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            GitCommitEditor(text: $model.commitMessage, placeholder: L("提交信息"))
                .frame(height: 64)

            HStack(spacing: 10) {
                Toggle(isOn: $model.amend) {
                    Text(L("修补上次提交"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .toggleStyle(.checkbox)
                .controlSize(.mini)

                Spacer()

                Button(action: { model.commit() }) {
                    HStack(spacing: 5) {
                        if model.isWorking {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        }
                        Text(commitLabel).font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(model.canCommit ? AppStyle.accent : AppStyle.hoverFill))
                    .foregroundStyle(model.canCommit ? Color.white : AppStyle.textTertiary)
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!model.canCommit)
            }
        }
        .padding(12)
        .background(AppStyle.windowBackground)
    }

    private var commitLabel: String {
        let n = model.stagedChanges.count
        return n > 0 ? L("提交 %ld", n) : L("提交")
    }
}

/// 单个变更行：状态徽标 + 文件名 + 悬停操作。点击选中以查看 diff。
private struct GitChangeRow: View {
    @ObservedObject var model: GitPanelModel
    let change: GitChange
    let staged: Bool
    @State private var hovering = false

    private var source: GitDiffSource {
        if staged { return .staged }
        return change.workTree == .untracked ? .untracked : .workTree
    }

    private var isSelected: Bool {
        model.selection?.path == change.path && model.selection?.source == source
    }

    private var state: GitChangeState { staged ? change.index : change.workTree }

    var body: some View {
        HStack(spacing: 8) {
            GitStatusBadge(state: state)
            fileName
            Spacer(minLength: 4)
            if hovering {
                actions
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { model.select(change, source: source) }
        .onHover { hovering = $0 }
        .contextMenu { GitMenus.change(model, change, staged: staged) }
    }

    private var fileName: some View {
        let url = URL(fileURLWithPath: change.path)
        let dir = url.deletingLastPathComponent().relativePath
        return HStack(spacing: 5) {
            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if dir != "." , !dir.isEmpty {
                Text(dir)
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 1) {
            if staged {
                rowButton("minus", L("取消暂存")) { model.unstage(change) }
            } else {
                rowButton("arrow.uturn.backward", L("丢弃改动")) { model.discard(change) }
                rowButton("plus", L("暂存")) { model.stage(change) }
            }
        }
    }

    private func rowButton(_ icon: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .buttonStyle(IconButtonStyle(size: 20))
        .help(help)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? AppStyle.activeFill : (hovering ? AppStyle.hoverFill : Color.clear))
            .padding(.horizontal, 6)
    }
}
