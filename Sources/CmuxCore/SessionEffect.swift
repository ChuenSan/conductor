import Foundation

/// 命令 reducer 产生的副作用，由应用层解释执行（创建/关闭真实终端 surface）。
public enum SessionEffect: Equatable {
    /// 为新 pane 创建一个终端，并在给定目录启动 shell。
    case createSurface(pane: PaneID, cwd: String)
    /// 关闭并释放该 pane 的终端。
    case closeSurface(pane: PaneID)
    /// 把键盘焦点给该 pane 的终端。
    case focusSurface(pane: PaneID)
}
