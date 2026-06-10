import AppKit
import CmuxCore

/// 一条可执行命令：稳定 id、标题、内置默认键位、执行体。
/// 命令面板/键位帮助/自定义键位都读这张表（高扩展）。
struct AppCommand {
    let id: String
    let title: String
    let defaultKeybinding: String?
    let run: () -> Void
}

/// 命令注册表：持有命令 + 维护 `[KeyChord: AppCommand]` 索引，键位分发 **O(1)**。
/// 有效键位 = `config.keybindings[id]` ?? 命令内置默认；config 变化时重建索引。
@MainActor
final class CommandRegistry {
    private(set) var commands: [AppCommand] = []
    private var index: [KeyChord: AppCommand] = [:]

    func register(_ commands: [AppCommand]) {
        self.commands = commands
        rebuildIndex()
    }

    /// 用当前配置的键位覆盖重建索引（config 热更新后调用）。
    func rebuildIndex() {
        let overrides = ConfigStore.shared.config.keybindings
        var idx: [KeyChord: AppCommand] = [:]
        for cmd in commands {
            guard let spec = overrides[cmd.id] ?? cmd.defaultKeybinding,
                  let chord = KeyChord(parsing: spec) else { continue }
            idx[chord] = cmd
        }
        index = idx
    }

    /// 命中则执行并返回 true（调用方据此吞掉事件）。
    @discardableResult
    func dispatch(_ chord: KeyChord) -> Bool {
        guard let cmd = index[chord] else { return false }
        cmd.run()
        return true
    }

    /// 某命令当前的有效键位串（供键位帮助/UI 展示）。
    func effectiveKeybinding(for id: String) -> String? {
        ConfigStore.shared.config.keybindings[id] ?? commands.first { $0.id == id }?.defaultKeybinding
    }
}

extension KeyChord {
    /// 把 AppKit 键盘事件归一成 KeyChord，用于查表匹配。
    init?(event: NSEvent) {
        var mods: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }

        let key: String
        switch event.keyCode {
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        case 36:  key = "enter"
        case 53:  key = "esc"
        case 48:  key = "tab"
        case 49:  key = "space"
        case 51:  key = "delete"
        default:
            guard let ch = event.charactersIgnoringModifiers?.lowercased(), let first = ch.first else { return nil }
            key = String(first)
        }
        self.init(modifiers: mods, key: key)
    }
}
