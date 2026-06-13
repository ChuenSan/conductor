import ConductorGit
import SwiftUI

/// 变更状态 → 单字母标记 + 颜色。对标 SourceGit / VS Code 的状态字母。
@MainActor
enum GitStatusStyle {
    static func letter(_ state: GitChangeState) -> String {
        switch state {
        case .none: " "
        case .modified: "M"
        case .typeChanged: "T"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "U"
        case .conflicted: "!"
        }
    }

    static func color(_ state: GitChangeState) -> Color {
        switch state {
        case .added, .copied: AppStyle.doneGreen
        case .modified, .typeChanged, .renamed: AppStyle.waitAmber
        case .deleted: AppStyle.errorRed
        case .untracked: AppStyle.doneGreen
        case .conflicted: AppStyle.errorRed
        case .none: AppStyle.textTertiary
        }
    }
}

/// 列表行里的状态字母小徽标。
struct GitStatusBadge: View {
    let state: GitChangeState

    var body: some View {
        Text(GitStatusStyle.letter(self.state))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(GitStatusStyle.color(self.state))
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(GitStatusStyle.color(self.state).opacity(0.14)))
    }
}
