import Foundation

/// 提交图泳道布局：给每个提交算一个列号（column），用于画分叉/合并连线。
/// 采用稳定泳道算法（列槽复用，第一父延续本列，多父开新列），便于画竖线 + 斜接。
public enum CommitGraphLayout {
    public struct Result: Sendable, Equatable {
        /// 与 commits 一一对应的列号。
        public var columns: [Int]
        /// 最大列号（决定图宽）。
        public var maxColumn: Int
    }

    /// commits 须按 git log 顺序（子在前、父在后）。纯函数。
    public static func compute(_ commits: [GitCommit]) -> Result {
        var lanes: [String?] = [] // 每列「期待出现的下一个 sha」
        var columns = [Int](repeating: 0, count: commits.count)
        var maxColumn = 0

        func firstFree() -> Int {
            if let i = lanes.firstIndex(where: { $0 == nil }) { return i }
            lanes.append(nil)
            return lanes.count - 1
        }

        for (i, commit) in commits.enumerated() {
            // 找到期待本提交的列；多个子收敛时，留第一个、其余释放（合并进本列）。
            var myCol = -1
            for (j, lane) in lanes.enumerated() where lane == commit.sha {
                if myCol == -1 {
                    myCol = j
                } else {
                    lanes[j] = nil
                }
            }
            if myCol == -1 { myCol = firstFree() }
            columns[i] = myCol

            let parents = commit.parents
            if parents.isEmpty {
                lanes[myCol] = nil
            } else {
                // 第一父延续本列。
                lanes[myCol] = parents[0]
                // 其余父：已有列在等它就复用，否则开新列。
                for p in parents.dropFirst() where !lanes.contains(p) {
                    let idx = firstFree()
                    lanes[idx] = p
                }
            }

            maxColumn = max(maxColumn, myCol, lanes.count - 1)
        }

        // 收尾：去掉尾部空列对宽度的高估。
        let usedMax = columns.max() ?? 0
        return Result(columns: columns, maxColumn: max(usedMax, maxColumn))
    }
}
