import ConductorGit
import SwiftUI

/// 右侧 Git 侧面板：变更 / 历史 / 分支三段。绑定当前工作目录，移植自 SourceGit 的工作流。
struct GitPanelView: View {
    @ObservedObject var model: GitPanelModel
    var onClose: () -> Void = {}
    /// 主题变 → 重渲染（AppStyle 跟随）。
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppStyle.separator)
            if model.isRepo {
                segmented
                Divider().overlay(AppStyle.separator)
            }
            content
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.windowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(AppStyle.separator).frame(width: 1).allowsHitTesting(false)
        }
        .overlay { inspectorOverlay }
        .overlay { promptOverlay }
        .overlay(alignment: .bottom) { errorBanner }
        .overlay(alignment: .bottom) { toastOverlay }
        .animation(Motion.snappy, value: model.inspector)
        .animation(Motion.snappy, value: model.prompt)
        .animation(Motion.snappy, value: model.toast)
        .animation(Motion.snappy, value: model.errorMessage)
    }

    @ViewBuilder
    private var promptOverlay: some View {
        if let prompt = model.prompt {
            GitPromptView(model: model, prompt: prompt)
                .id(prompt.id)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var inspectorOverlay: some View {
        if let inspector = model.inspector {
            GitInspectorView(model: model, inspector: inspector)
                .id(inspector.id)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(AppStyle.elevated))
                .overlay(Capsule().stroke(AppStyle.separator))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    if model.toast == toast { model.toast = nil }
                }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("源代码管理"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                if model.isRepo {
                    branchChip
                } else if let dir = model.directory {
                    Text(Self.shortPath(dir))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            if model.isRepo {
                remoteButton("arrow.down.circle", L("拉取 (fetch)")) { model.fetch() }
                remoteButton("arrow.down.to.line.circle", L("拉取并合并 (pull)")) { model.pull() }
                remoteButton("arrow.up.circle", L("推送 (push)")) { model.push() }
                Button(action: { model.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .rotationEffect(.degrees(model.isLoading ? 360 : 0))
                        .animation(model.isLoading
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default, value: model.isLoading)
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help(L("刷新"))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppStyle.hoverFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func remoteButton(_ icon: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .buttonStyle(IconButtonStyle(size: 26))
        .help(help)
        .disabled(model.isWorking)
    }

    private var branchChip: some View {
        HStack(spacing: 6) {
            Image(systemName: model.head.isDetached ? "scope" : "arrow.triangle.branch")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
            Text(model.head.branch.isEmpty ? L("（无分支）") : model.head.branch)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
            if model.head.ahead > 0 {
                trackLabel("\(model.head.ahead)", system: "arrow.up")
            }
            if model.head.behind > 0 {
                trackLabel("\(model.head.behind)", system: "arrow.down")
            }
        }
    }

    private func trackLabel(_ text: String, system: String) -> some View {
        HStack(spacing: 1) {
            Image(systemName: system).font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(AppStyle.textTertiary)
    }

    // MARK: - 分段

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(GitTab.allCases) { tab in
                let selected = model.tab == tab
                Button {
                    withAnimation(Motion.snappy) { model.tab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? AppStyle.accent : AppStyle.textTertiary)
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textTertiary)
                        if tab == .changes, !model.changes.isEmpty {
                            Text("\(model.changes.count)")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(AppStyle.textTertiary)
                        }
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? AppStyle.elevated : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppStyle.hoverFill))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if model.isLoading, !model.isRepo {
            centeredMessage(spinner: true, L("加载中…"))
        } else if model.directory == nil {
            centeredMessage(icon: "folder", L("打开一个工作区以管理 Git"))
        } else if !model.isRepo {
            notRepoState
        } else {
            switch model.tab {
            case .changes: GitChangesView(model: model)
            case .history: GitHistoryView(model: model)
            case .branches: GitBranchesView(model: model)
            }
        }
    }

    private var notRepoState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppStyle.textTertiary)
            Text(L("当前目录不是 Git 仓库"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppStyle.textSecondary)
            if let dir = model.directory {
                Text(Self.shortPath(dir))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centeredMessage(spinner: Bool = false, icon: String? = nil, _ text: String) -> some View {
        VStack(spacing: 12) {
            if spinner {
                ProgressView().controlSize(.small)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppStyle.errorRed)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(3)
                Spacer(minLength: 4)
                Button(action: { model.errorMessage = nil }) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppStyle.elevated))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AppStyle.errorRed.opacity(0.4)))
            .padding(12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
