import Foundation
import ConductorCore

extension Notification.Name {
    /// 请求打开「联动规则」面板（自动化 / 菜单 / 命令面板触发，侧栏监听）。
    static let conductorOpenChoreography = Notification.Name("conductor.openChoreography")
}

/// ③ 联动：一条命令在某 pane 跑完时，自动做点什么。
///
/// 规则是**会话级**的——pane id 每次启动都重生，持久化一个指向具体 pane 的规则没意义；
/// 这是「为当前工作现场接线」：比如「build pane 一失败就在 deploy pane 别跑」「测试一过就通知我」。
/// 触发源是 ② 已验证可用的命令完成信号（退出码 + 时长）。
struct ChoreographyRule: Identifiable, Equatable {
    let id: UUID
    var enabled: Bool
    var trigger: ChoreoTrigger
    /// nil = 任意 pane 触发；否则只有这个 pane 跑完命令才算。
    var source: PaneID?
    var action: ChoreoAction

    init(id: UUID = UUID(), enabled: Bool = true,
         trigger: ChoreoTrigger, source: PaneID? = nil, action: ChoreoAction) {
        self.id = id
        self.enabled = enabled
        self.trigger = trigger
        self.source = source
        self.action = action
    }
}

enum ChoreoTrigger: String, CaseIterable, Equatable, Sendable {
    case anyFinish   // 任何命令跑完
    case success     // 退出码 0
    case failure     // 退出码非 0

    var label: String {
        switch self {
        case .anyFinish: return "命令完成"
        case .success:   return "命令成功"
        case .failure:   return "命令失败"
        }
    }
}

enum ChoreoAction: Equatable {
    case notify                                       // 发通知（走桌面通知/账本同一出口）
    case focusSource                                  // 跳到触发的 pane
    case runCommand(target: PaneID, command: String)  // 在某 pane 跑一条命令

    var kindLabel: String {
        switch self {
        case .notify:     return "通知我"
        case .focusSource: return "跳到该终端"
        case .runCommand: return "运行命令"
        }
    }
}

struct ChoreographySuppression: Equatable {
    private var counts: [PaneID: Int] = [:]

    mutating func suppressNextCommand(in pane: PaneID) {
        counts[pane, default: 0] += 1
    }

    mutating func consume(for pane: PaneID) -> Bool {
        guard let count = counts[pane], count > 0 else { return false }
        if count == 1 {
            counts[pane] = nil
        } else {
            counts[pane] = count - 1
        }
        return true
    }
}
