import ConductorGit
import SwiftUI

/// 分支段：本地分支（可点击切换）+ 远程分支（只读）。
struct GitBranchesView: View {
    @ObservedObject var model: GitPanelModel

    private var locals: [GitBranch] { model.branches.filter(\.isLocal) }
    private var remotes: [GitBranch] { model.branches.filter { !$0.isLocal } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !locals.isEmpty {
                    Section {
                        ForEach(locals) { branch in
                            GitBranchRow(model: model, branch: branch)
                        }
                    } header: {
                        header(L("本地分支"), count: locals.count)
                    }
                }
                if !remotes.isEmpty {
                    Section {
                        ForEach(remotes) { branch in
                            GitBranchRow(model: model, branch: branch)
                        }
                    } header: {
                        header(L("远程分支"), count: remotes.count)
                    }
                }
                if !model.tags.isEmpty {
                    Section {
                        ForEach(model.tags) { tag in
                            GitTagRow(model: model, tag: tag)
                        }
                    } header: {
                        header(L("标签"), count: model.tags.count)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
            Text("\(count)")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(AppStyle.windowBackground)
    }
}

private struct GitBranchRow: View {
    @ObservedObject var model: GitPanelModel
    let branch: GitBranch
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(branch.isCurrent ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 16)

            Text(branch.isLocal ? branch.name : branch.friendlyName)
                .font(.system(size: 12, weight: branch.isCurrent ? .semibold : .regular))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            if branch.isTrackStatusVisible {
                Text(branch.trackStatusDescription)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
            }

            Spacer(minLength: 4)

            if hovering, branch.isLocal, !branch.isCurrent {
                Text(L("切换"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovering ? AppStyle.hoverFill : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if branch.isLocal { model.checkout(branch) } }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        if branch.isLocal {
            GitMenus.localBranch(model, branch)
        } else {
            GitMenus.remoteBranch(model, branch)
        }
    }
}

/// tag 行（在分支段的标签分区）。
private struct GitTagRow: View {
    @ObservedObject var model: GitPanelModel
    let tag: GitTag
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tag")
                .font(.system(size: 11)).foregroundStyle(AppStyle.waitAmber).frame(width: 16)
            Text(tag.name)
                .font(.system(size: 12)).foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(String(tag.sha.prefix(7)))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(AppStyle.textTertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(hovering ? AppStyle.hoverFill : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { GitMenus.tag(model, tag) }
    }
}
