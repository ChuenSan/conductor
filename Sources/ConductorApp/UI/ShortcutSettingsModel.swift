import ConductorCore
import Foundation

enum ShortcutSettingsFilter: String, CaseIterable, Equatable {
    case all
    case modified
    case unassigned
    case conflicts

    var title: String {
        switch self {
        case .all: return L("全部")
        case .modified: return L("已修改")
        case .unassigned: return L("未分配")
        case .conflicts: return L("冲突")
        }
    }
}

struct ShortcutSettingsRow: Identifiable, Equatable {
    let id: String
    let title: String
    let scope: CommandDeckLayer
    let defaultKeybinding: String?
    let effectiveKeybinding: String?
    let isModified: Bool
    let isDisabled: Bool
    let conflictingCommandTitles: [String]

    var isUnassigned: Bool { effectiveKeybinding == nil }
    var hasConflicts: Bool { !conflictingCommandTitles.isEmpty }
    var symbolizedKeybinding: String? { effectiveKeybinding.map(ShortcutSymbolizer.symbolize) }
}

struct ShortcutSettingsGroup: Equatable {
    let scope: CommandDeckLayer
    let title: String
    let rows: [ShortcutSettingsRow]
}

struct ShortcutSettingsEditError: Error, Equatable {
    let message: String
}

enum ShortcutSettingsModel {
    static func rows(commands: [AppCommand], overrides: [String: String]) -> [ShortcutSettingsRow] {
        let baseRows = commands.map { command in
            row(for: command, overrides: overrides, conflicts: [:])
        }
        let conflictTitles = conflicts(in: baseRows)
        return commands.map { command in
            row(for: command, overrides: overrides, conflicts: conflictTitles)
        }
    }

    static func count(_ rows: [ShortcutSettingsRow], matching filter: ShortcutSettingsFilter) -> Int {
        rows.filter { matches($0, filter: filter) }.count
    }

    static func filterCounts(for rows: [ShortcutSettingsRow]) -> [ShortcutSettingsFilter: Int] {
        Dictionary(uniqueKeysWithValues: ShortcutSettingsFilter.allCases.map { filter in
            (filter, count(rows, matching: filter))
        })
    }

    static func groupedRows(_ rows: [ShortcutSettingsRow]) -> [ShortcutSettingsGroup] {
        CommandDeckLayer.allCases.compactMap { scope in
            let scopedRows = rows.filter { $0.scope == scope }
            guard !scopedRows.isEmpty else { return nil }
            return ShortcutSettingsGroup(scope: scope, title: scope.title, rows: scopedRows)
        }
    }

    static func filteredRows(
        _ rows: [ShortcutSettingsRow],
        query: String,
        filter: ShortcutSettingsFilter
    ) -> [ShortcutSettingsRow] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            matches(row, filter: filter) && matches(row, query: normalizedQuery)
        }
    }

    static func configByAssigningShortcut(
        commandID: String,
        shortcut: String,
        commands: [AppCommand],
        currentKeybindings: [String: String]
    ) -> Result<[String: String], ShortcutSettingsEditError> {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let canonical = canonicalSpec(trimmed) else {
            return .failure(ShortcutSettingsEditError(message: L("无法识别快捷键")))
        }

        var next = currentKeybindings
        if commands.first(where: { $0.id == commandID })?.defaultKeybinding.flatMap(canonicalSpec) == canonical {
            next.removeValue(forKey: commandID)
        } else {
            next[commandID] = canonical
        }

        let candidateRows = rows(commands: commands, overrides: next)
        guard let row = candidateRows.first(where: { $0.id == commandID }) else {
            return .success(next)
        }
        guard row.conflictingCommandTitles.isEmpty else {
            let binding = row.effectiveKeybinding.map(commandFirstSymbolizedSpec) ?? canonical
            return .failure(ShortcutSettingsEditError(
                message: L("%@ 与 %@ 冲突", binding, row.conflictingCommandTitles.joined(separator: "、"))
            ))
        }
        return .success(next)
    }

    static func configByDisablingShortcut(
        commandID: String,
        currentKeybindings: [String: String]
    ) -> [String: String] {
        var next = currentKeybindings
        next[commandID] = ""
        return next
    }

    static func configByResettingShortcut(
        commandID: String,
        currentKeybindings: [String: String]
    ) -> [String: String] {
        var next = currentKeybindings
        next.removeValue(forKey: commandID)
        return next
    }

    static func canonicalSpec(_ raw: String) -> String? {
        guard let chord = KeyChord(parsing: raw) else { return nil }
        return canonicalSpec(for: chord)
    }

    static func canonicalSpec(for chord: KeyChord) -> String {
        var parts: [String] = []
        if chord.modifiers.contains(.command) { parts.append("cmd") }
        if chord.modifiers.contains(.control) { parts.append("ctrl") }
        if chord.modifiers.contains(.option) { parts.append("alt") }
        if chord.modifiers.contains(.shift) { parts.append("shift") }
        parts.append(chord.key)
        return parts.joined(separator: "+")
    }

    private static func row(
        for command: AppCommand,
        overrides: [String: String],
        conflicts: [String: [String]]
    ) -> ShortcutSettingsRow {
        let override = overrides[command.id]
        let effective = effectiveKeybinding(for: command, override: override)
        return ShortcutSettingsRow(
            id: command.id,
            title: command.title,
            scope: command.scope,
            defaultKeybinding: command.defaultKeybinding.flatMap(canonicalSpec),
            effectiveKeybinding: effective,
            isModified: override != nil,
            isDisabled: override?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
            conflictingCommandTitles: conflicts[command.id] ?? []
        )
    }

    private static func effectiveKeybinding(for command: AppCommand, override: String?) -> String? {
        if let override {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return canonicalSpec(trimmed) ?? trimmed.lowercased()
        }
        return command.defaultKeybinding.flatMap(canonicalSpec)
    }

    private static func conflicts(in rows: [ShortcutSettingsRow]) -> [String: [String]] {
        var rowsByChord: [KeyChord: [ShortcutSettingsRow]] = [:]
        for row in rows {
            guard let spec = row.effectiveKeybinding, let chord = KeyChord(parsing: spec) else { continue }
            rowsByChord[chord, default: []].append(row)
        }

        var result: [String: [String]] = [:]
        for conflictingRows in rowsByChord.values where conflictingRows.count > 1 {
            for row in conflictingRows {
                result[row.id] = conflictingRows
                    .filter { $0.id != row.id }
                    .map(\.title)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
        }
        return result
    }

    private static func matches(_ row: ShortcutSettingsRow, filter: ShortcutSettingsFilter) -> Bool {
        switch filter {
        case .all: return true
        case .modified: return row.isModified
        case .unassigned: return row.isUnassigned
        case .conflicts: return row.hasConflicts
        }
    }

    private static func matches(_ row: ShortcutSettingsRow, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let values = [
            row.title,
            row.id,
            row.scope.title,
            row.effectiveKeybinding ?? "",
            row.symbolizedKeybinding ?? "",
            row.effectiveKeybinding.map(commandFirstSymbolizedSpec) ?? ""
        ]
        return values.contains { $0.lowercased().contains(query) }
    }

    private static func commandFirstSymbolizedSpec(_ spec: String) -> String {
        guard let chord = KeyChord(parsing: spec) else { return spec }
        var output = ""
        if chord.modifiers.contains(.command) { output += "⌘" }
        if chord.modifiers.contains(.shift) { output += "⇧" }
        if chord.modifiers.contains(.option) { output += "⌥" }
        if chord.modifiers.contains(.control) { output += "⌃" }
        return output + ShortcutSymbolizer.symbolize(chord.key)
    }
}
