import ConductorGit
import SwiftUI

/// 历史段：带分叉/合并连线的提交图 + 每行提交信息。右键是完整提交操作菜单。
struct GitHistoryView: View {
    @ObservedObject var model: GitPanelModel

    private let rowHeight: CGFloat = 46
    private let laneWidth: CGFloat = 14

    var body: some View {
        if model.commits.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "clock").font(.system(size: 28, weight: .light))
                    .foregroundStyle(AppStyle.textTertiary)
                Text(L("暂无提交")).font(.system(size: 12.5)).foregroundStyle(AppStyle.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            graph
        }
    }

    private var graph: some View {
        let commits = model.commits
        let layout = CommitGraphLayout.compute(commits)
        let gutter = CGFloat(layout.maxColumn + 1) * laneWidth + 8

        return ScrollView {
            ZStack(alignment: .topLeading) {
                GitGraphCanvas(
                    commits: commits, columns: layout.columns,
                    rowHeight: rowHeight, laneWidth: laneWidth)
                    .frame(width: gutter, height: rowHeight * CGFloat(commits.count))

                VStack(spacing: 0) {
                    ForEach(Array(commits.enumerated()), id: \.element.id) { _, commit in
                        GitGraphRow(model: model, commit: commit, leading: gutter, height: rowHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 一行提交（图右侧）。节点圆点由 Canvas 画，这里只放文本 + 装饰 + 右键菜单。
private struct GitGraphRow: View {
    @ObservedObject var model: GitPanelModel
    let commit: GitCommit
    let leading: CGFloat
    let height: CGFloat
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    ForEach(Array(commit.decorators.enumerated()), id: \.offset) { _, d in
                        decoratorChip(d)
                    }
                    Text(commit.subject)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    Text(commit.author.name).font(.system(size: 10)).foregroundStyle(AppStyle.textSecondary)
                    Text(GitRelativeDate.string(commit.authorDate))
                        .font(.system(size: 10)).foregroundStyle(AppStyle.textTertiary)
                    Spacer(minLength: 4)
                    Text(commit.shortSHA.prefix(7))
                        .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(AppStyle.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, leading)
        .padding(.trailing, 12)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? AppStyle.hoverFill : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { GitMenus.commit(model, commit) }
    }

    private func decoratorChip(_ d: GitDecorator) -> some View {
        let isTag = d.kind == .tag
        let color: Color = isTag ? AppStyle.waitAmber : AppStyle.accent
        let name = d.kind == .currentCommitHead ? "HEAD" : d.name
        return HStack(spacing: 2) {
            Image(systemName: isTag ? "tag.fill" : "arrow.triangle.branch")
                .font(.system(size: 7, weight: .bold))
            Text(name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// 用 Canvas 画整张提交图：泳道竖线 + 父子连线 + 节点。
private struct GitGraphCanvas: View {
    let commits: [GitCommit]
    let columns: [Int]
    let rowHeight: CGFloat
    let laneWidth: CGFloat

    private static let palette: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 1.0),
        Color(red: 0.40, green: 0.78, blue: 0.45),
        Color(red: 0.95, green: 0.62, blue: 0.20),
        Color(red: 0.85, green: 0.45, blue: 0.85),
        Color(red: 0.35, green: 0.78, blue: 0.80),
        Color(red: 0.92, green: 0.45, blue: 0.50),
    ]

    private func laneColor(_ col: Int) -> Color { Self.palette[col % Self.palette.count] }
    private func colX(_ col: Int) -> CGFloat { laneWidth / 2 + CGFloat(col) * laneWidth }
    private func rowY(_ i: Int) -> CGFloat { CGFloat(i) * rowHeight + rowHeight / 2 }

    var body: some View {
        Canvas { ctx, _ in
            var indexBySHA: [String: Int] = [:]
            for (i, c) in commits.enumerated() { indexBySHA[c.sha] = i }

            // 连线（画在节点下层）。
            for (i, c) in commits.enumerated() {
                let childPt = CGPoint(x: colX(columns[i]), y: rowY(i))
                for parent in c.parents {
                    guard let pj = indexBySHA[parent] else { continue }
                    let parentPt = CGPoint(x: colX(columns[pj]), y: rowY(pj))
                    var path = Path()
                    path.move(to: childPt)
                    if abs(childPt.x - parentPt.x) < 0.5 {
                        path.addLine(to: parentPt)
                    } else {
                        // 在子列向下走，再在父行附近弯入父列。
                        let bendY = parentPt.y - rowHeight * 0.5
                        path.addLine(to: CGPoint(x: childPt.x, y: bendY))
                        path.addQuadCurve(to: parentPt, control: CGPoint(x: childPt.x, y: parentPt.y))
                    }
                    ctx.stroke(path, with: .color(laneColor(columns[pj])), lineWidth: 1.6)
                }
            }

            // 节点。
            for (i, c) in commits.enumerated() {
                let pt = CGPoint(x: colX(columns[i]), y: rowY(i))
                let r: CGFloat = c.isCurrentHead ? 5 : 3.5
                let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(laneColor(columns[i])))
                if c.isCurrentHead {
                    ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                               with: .color(laneColor(columns[i])), lineWidth: 1.4)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 极简相对时间。
enum GitRelativeDate {
    static func string(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return L("刚刚") }
        let minutes = seconds / 60
        if minutes < 60 { return L("%ld 分钟前", minutes) }
        let hours = minutes / 60
        if hours < 24 { return L("%ld 小时前", hours) }
        let days = hours / 24
        if days < 30 { return L("%ld 天前", days) }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
