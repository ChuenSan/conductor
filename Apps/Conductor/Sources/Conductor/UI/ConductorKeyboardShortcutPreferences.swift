import AppKit
import Foundation

private enum ArrowDirection {
    case left
    case right
    case up
    case down
}

struct KeyboardShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let command = KeyboardShortcutModifiers(rawValue: 1 << 0)
    static let shift = KeyboardShortcutModifiers(rawValue: 1 << 1)
    static let option = KeyboardShortcutModifiers(rawValue: 1 << 2)
    static let control = KeyboardShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        let flags = eventFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        var value: KeyboardShortcutModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        self = value
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }

    var displayParts: [String] {
        var parts: [String] = []
        if contains(.control) { parts.append("Ctrl") }
        if contains(.command) { parts.append("Cmd") }
        if contains(.option) { parts.append("Opt") }
        if contains(.shift) { parts.append("Shift") }
        return parts
    }
}

struct KeyboardShortcutDefinition: Codable, Equatable, Hashable, Sendable {
    enum Key: String, Codable, Equatable, Hashable, Sendable {
        case character
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
    }

    var key: String
    var keyKind: Key
    var modifiers: KeyboardShortcutModifiers

    init(key: String, keyKind: Key = .character, modifiers: KeyboardShortcutModifiers) {
        self.key = key.lowercased()
        self.keyKind = keyKind
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let modifiers = KeyboardShortcutModifiers(eventFlags: event.modifierFlags)
        guard modifiers.contains(.command) else { return nil }
        self.modifiers = modifiers

        if let direction = event.arrowDirection {
            switch direction {
            case .left:
                self.key = "left"
                self.keyKind = .leftArrow
            case .right:
                self.key = "right"
                self.keyKind = .rightArrow
            case .up:
                self.key = "up"
                self.keyKind = .upArrow
            case .down:
                self.key = "down"
                self.keyKind = .downArrow
            }
            return
        }

        guard let character = event.charactersIgnoringModifiers?.lowercased(),
              let first = character.first else {
            return nil
        }
        self.key = String(first)
        self.keyKind = .character
    }

    var displayTitle: String {
        (modifiers.displayParts + [displayKey]).joined(separator: "-")
    }

    var menuKeyEquivalent: String {
        keyKind == .character ? key : ""
    }

    var menuModifierFlags: NSEvent.ModifierFlags {
        modifiers.eventFlags
    }

    var isReservedSystemShortcut: Bool {
        keyKind == .character && modifiers == [.command] && key == "q"
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let other = KeyboardShortcutDefinition(event: event) else { return false }
        return other == self
    }

    private var displayKey: String {
        switch keyKind {
        case .character:
            key.uppercased()
        case .leftArrow:
            "←"
        case .rightArrow:
            "→"
        case .upArrow:
            "↑"
        case .downArrow:
            "↓"
        }
    }
}

struct KeyboardShortcutPreferences: Codable, Equatable {
    var customShortcuts: [String: KeyboardShortcutDefinition]

    init(customShortcuts: [String: KeyboardShortcutDefinition] = [:]) {
        self.customShortcuts = customShortcuts
    }

    func shortcut(for command: ConductorShellCommand) -> KeyboardShortcutDefinition? {
        if let customShortcut = customShortcuts[command.rawValue] {
            return customShortcut
        }
        guard let defaultShortcut = Self.defaultShortcuts[command],
              !isDefaultShortcutShadowed(defaultShortcut, for: command) else {
            return nil
        }
        return defaultShortcut
    }

    func displayShortcut(for command: ConductorShellCommand, fallback: String) -> String {
        if let shortcut = shortcut(for: command) {
            return shortcut.displayTitle
        }
        if Self.defaultShortcuts[command] != nil {
            return ConductorLocalization.text(zh: "未设置", en: "Unassigned")
        }
        return fallback
    }

    func command(matching event: NSEvent, in commands: [ConductorShellCommand] = ConductorShellCommand.allCases) -> ConductorShellCommand? {
        for command in commands {
            if let shortcut = customShortcuts[command.rawValue], shortcut.matches(event) {
                return command
            }
        }
        for command in commands where customShortcuts[command.rawValue] == nil {
            if let shortcut = Self.defaultShortcuts[command],
               !isDefaultShortcutShadowed(shortcut, for: command),
               shortcut.matches(event) {
                return command
            }
        }
        return nil
    }

    mutating func set(_ shortcut: KeyboardShortcutDefinition, for command: ConductorShellCommand) {
        customShortcuts = customShortcuts.filter { key, existingShortcut in
            key == command.rawValue || existingShortcut != shortcut
        }
        customShortcuts[command.rawValue] = shortcut
    }

    mutating func reset(_ command: ConductorShellCommand) {
        customShortcuts.removeValue(forKey: command.rawValue)
    }

    mutating func resetAll() {
        customShortcuts.removeAll()
    }

    private func isDefaultShortcutShadowed(
        _ defaultShortcut: KeyboardShortcutDefinition,
        for command: ConductorShellCommand
    ) -> Bool {
        customShortcuts.contains { key, shortcut in
            key != command.rawValue && shortcut == defaultShortcut
        }
    }

    private static func shortcut(
        _ key: String,
        _ modifiers: KeyboardShortcutModifiers = [.command]
    ) -> KeyboardShortcutDefinition {
        KeyboardShortcutDefinition(key: key, modifiers: modifiers)
    }

    private static func arrow(
        _ keyKind: KeyboardShortcutDefinition.Key,
        _ modifiers: KeyboardShortcutModifiers
    ) -> KeyboardShortcutDefinition {
        let key: String
        switch keyKind {
        case .leftArrow:
            key = "left"
        case .rightArrow:
            key = "right"
        case .upArrow:
            key = "up"
        case .downArrow:
            key = "down"
        case .character:
            key = ""
        }
        return KeyboardShortcutDefinition(key: key, keyKind: keyKind, modifiers: modifiers)
    }

    static let defaultShortcuts: [ConductorShellCommand: KeyboardShortcutDefinition] = [
        .newWorkspace: shortcut("n"),
        .newTerminal: shortcut("t"),
        .newWebTab: shortcut("t", [.command, .shift]),
        .focusWebAddress: shortcut("l"),
        .reloadSelectedWebTab: shortcut("r"),
        .closeSelectedTab: shortcut("w"),
        .closeFocusedPane: shortcut("w", [.command, .shift]),
        .splitRight: shortcut("d"),
        .splitDown: shortcut("d", [.command, .shift]),
        .selectNextTab: shortcut("]"),
        .selectPreviousTab: shortcut("["),
        .focusNextPane: shortcut("]", [.command, .shift]),
        .focusPreviousPane: shortcut("[", [.command, .shift]),
        .focusPaneLeft: arrow(.leftArrow, [.command, .option]),
        .focusPaneRight: arrow(.rightArrow, [.command, .option]),
        .focusPaneUp: arrow(.upArrow, [.command, .option]),
        .focusPaneDown: arrow(.downArrow, [.command, .option]),
        .resizePaneLeft: arrow(.leftArrow, [.command, .shift]),
        .resizePaneRight: arrow(.rightArrow, [.command, .shift]),
        .resizePaneUp: arrow(.upArrow, [.command, .shift]),
        .resizePaneDown: arrow(.downArrow, [.command, .shift]),
        .equalizeSplits: shortcut("=", [.command, .shift]),
        .toggleZoom: shortcut("z", [.command, .option]),
        .moveTabLeft: shortcut(",", [.command, .shift]),
        .moveTabRight: shortcut(".", [.command, .shift]),
        .moveTabToNextPane: shortcut("m", [.command, .option]),
        .moveTabToNewRightSplit: shortcut("m", [.command, .option, .shift]),
        .toggleCommandPalette: shortcut("k"),
        .toggleWorkspaceOverview: shortcut("o"),
        .toggleSettings: shortcut(","),
        .toggleFullScreen: shortcut("f", [.control, .command]),
        .showTerminalSearch: shortcut("f"),
        .findNext: shortcut("g"),
        .findPrevious: shortcut("g", [.command, .shift]),
        .flashFocusedPane: shortcut("h", [.command, .shift])
    ]
}

private extension NSEvent {
    var arrowDirection: ArrowDirection? {
        switch keyCode {
        case 123:
            .left
        case 124:
            .right
        case 125:
            .down
        case 126:
            .up
        default:
            nil
        }
    }
}
