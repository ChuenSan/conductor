import ConductorGit
import SwiftUI

/// 各类行的右键菜单。集中放这里，行视图只 `.contextMenu { GitMenus.xxx(...) }`。
/// 对齐 SourceGit 的菜单项集合。
enum GitMenus {
    // MARK: 提交

    @ViewBuilder
    static func commit(_ model: GitPanelModel, _ c: GitCommit) -> some View {
        Button { model.checkoutCommit(c) } label: { Label(L("检出此提交"), systemImage: "arrow.right.circle") }
        Divider()
        Button { model.promptCreateBranch(basedOn: c.sha, baseLabel: c.shortSHA) } label: {
            Label(L("以此为基新建分支…"), systemImage: "arrow.triangle.branch")
        }
        Button { model.promptCreateTag(basedOn: c.sha, baseLabel: c.shortSHA) } label: {
            Label(L("在此打标签…"), systemImage: "tag")
        }
        Divider()
        Button { model.promptResetTo(c) } label: { Label(L("重置当前分支到此…"), systemImage: "arrow.uturn.backward") }
        Button { model.revertCommit(c) } label: { Label(L("回滚此提交"), systemImage: "arrow.uturn.left.circle") }
        Button { model.cherryPick(c) } label: { Label(L("拣选到当前分支"), systemImage: "hand.point.up.left") }
        Button { model.rebaseOnto(c) } label: { Label(L("变基当前分支到此"), systemImage: "arrow.triangle.pull") }
        Divider()
        Button { model.saveCommitAsPatch(c) } label: { Label(L("存为补丁…"), systemImage: "doc.badge.arrow.up") }
        Menu(L("复制")) {
            Button(L("提交 SHA")) { model.copyText(c.sha) }
            Button(L("短 SHA")) { model.copyText(c.shortSHA) }
            Button(L("标题")) { model.copyText(c.subject) }
            Button(L("作者")) { model.copyText("\(c.author.name) <\(c.author.email)>") }
            Button(L("提交信息")) { model.copyCommitMessage(c) }
        }
    }

    // MARK: 文件变更

    @ViewBuilder
    static func change(_ model: GitPanelModel, _ c: GitChange, staged: Bool) -> some View {
        if c.isConflicted {
            Button { model.resolveConflict(c, useMine: true) } label: { Label(L("用我方版本"), systemImage: "person") }
            Button { model.resolveConflict(c, useMine: false) } label: { Label(L("用对方版本"), systemImage: "person.2") }
            Divider()
        }
        if staged {
            Button { model.unstage(c) } label: { Label(L("取消暂存"), systemImage: "minus.circle") }
        } else {
            Button { model.stage(c) } label: { Label(L("暂存"), systemImage: "plus.circle") }
            Button(role: .destructive) { model.discard(c) } label: { Label(L("丢弃改动"), systemImage: "arrow.uturn.backward") }
        }
        Button { model.stashFile(c) } label: { Label(L("贮藏此文件"), systemImage: "tray.and.arrow.down") }
        Divider()
        Button { model.openBlame(path: c.path) } label: { Label(L("追溯 (Blame)"), systemImage: "person.crop.rectangle.stack") }
        Button { model.openFileHistory(path: c.path) } label: { Label(L("文件历史"), systemImage: "clock.arrow.circlepath") }
        Divider()
        Button { model.revealInFinder(c) } label: { Label(L("在访达中显示"), systemImage: "folder") }
        Button { model.openFile(c) } label: { Label(L("打开文件"), systemImage: "doc") }
        Menu(L("复制")) {
            Button(L("相对路径")) { model.copyText(c.path) }
            Button(L("完整路径")) { model.copyAbsolutePath(c) }
        }
        Divider()
        Button { model.setAssumeUnchanged(c, assume: true) } label: { Label(L("假定未改动"), systemImage: "eye.slash") }
        Button { model.addToGitIgnore(c) } label: { Label(L("加入 .gitignore"), systemImage: "nosign") }
        Button { model.saveFileAsPatch(c, staged: staged) } label: { Label(L("存为补丁…"), systemImage: "doc.badge.arrow.up") }
    }

    // MARK: 分支

    @ViewBuilder
    static func localBranch(_ model: GitPanelModel, _ b: GitBranch) -> some View {
        Button { model.checkout(b) } label: { Label(L("检出"), systemImage: "arrow.right.circle") }
            .disabled(b.isCurrent)
        Button { model.mergeBranch(b) } label: { Label(L("合并到当前分支"), systemImage: "arrow.triangle.merge") }
            .disabled(b.isCurrent)
        Button { model.rebaseOntoBranch(b) } label: { Label(L("变基当前分支到此"), systemImage: "arrow.triangle.pull") }
            .disabled(b.isCurrent)
        Divider()
        Button { model.promptCreateBranch(basedOn: b.name, baseLabel: b.name) } label: {
            Label(L("以此为基新建分支…"), systemImage: "arrow.triangle.branch")
        }
        Button { model.promptCreateTag(basedOn: b.name, baseLabel: b.name) } label: {
            Label(L("在此打标签…"), systemImage: "tag")
        }
        Divider()
        Button { model.pushBranch(b) } label: { Label(L("推送"), systemImage: "arrow.up.circle") }
        Button { model.promptSetUpstream(b) } label: { Label(L("设置上游…"), systemImage: "link") }
        Button { model.promptRenameBranch(b) } label: { Label(L("重命名…"), systemImage: "pencil") }
        Button(role: .destructive) { model.promptDeleteBranch(b) } label: { Label(L("删除"), systemImage: "trash") }
            .disabled(b.isCurrent)
        Divider()
        Button { model.copyText(b.friendlyName) } label: { Label(L("复制分支名"), systemImage: "doc.on.doc") }
    }

    @ViewBuilder
    static func remoteBranch(_ model: GitPanelModel, _ b: GitBranch) -> some View {
        Button { model.checkoutRemoteAsLocal(b) } label: { Label(L("检出为本地分支"), systemImage: "arrow.down.circle") }
        Button(role: .destructive) { model.promptDeleteBranch(b) } label: { Label(L("删除远程分支"), systemImage: "trash") }
        Divider()
        Button { model.copyText(b.friendlyName) } label: { Label(L("复制分支名"), systemImage: "doc.on.doc") }
    }

    // MARK: tag

    @ViewBuilder
    static func tag(_ model: GitPanelModel, _ t: GitTag) -> some View {
        Button { model.promptCreateBranch(basedOn: t.name, baseLabel: t.name) } label: {
            Label(L("以此为基新建分支…"), systemImage: "arrow.triangle.branch")
        }
        Button { model.pushTag(t) } label: { Label(L("推送标签"), systemImage: "arrow.up.circle") }
        Button(role: .destructive) { model.promptDeleteTag(t) } label: { Label(L("删除"), systemImage: "trash") }
        Divider()
        Button { model.copyText(t.name) } label: { Label(L("复制标签名"), systemImage: "doc.on.doc") }
    }

    // MARK: stash

    @ViewBuilder
    static func stash(_ model: GitPanelModel, _ s: GitStash) -> some View {
        Button { model.applyStash(s) } label: { Label(L("应用"), systemImage: "tray.and.arrow.up") }
        Button { model.popStash(s) } label: { Label(L("应用并删除"), systemImage: "tray.and.arrow.up.fill") }
        Button { model.promptStashToBranch(s) } label: { Label(L("基于此新建分支…"), systemImage: "arrow.triangle.branch") }
        Divider()
        Button { model.copyText(s.message) } label: { Label(L("复制描述"), systemImage: "doc.on.doc") }
        Button(role: .destructive) { model.promptDropStash(s) } label: { Label(L("丢弃"), systemImage: "trash") }
    }
}
