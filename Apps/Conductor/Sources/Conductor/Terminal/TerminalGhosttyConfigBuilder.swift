import Foundation

struct TerminalGhosttyConfigBuilder {
    private static let defaultScrollbackLimit = "50000000"
    private static let legacyScrollbackLimits = [
        "10000": "10000000",
        "50000": "50000000",
        "100000": "100000000"
    ]

    static func configText(
        theme: TerminalTheme,
        terminalFontSize: CGFloat,
        renderer: TerminalRendererPreferences
    ) -> String {
        let resolvedFontSize = AppearancePreferences.clampedTerminalFontSize(terminalFontSize)
        let fontSizeText = String(format: "%.1f", Double(resolvedFontSize))
        let fontFamily = TerminalFontLibrary.resolvedFamilyName(
            preset: renderer.fontPreset,
            customFamilyName: renderer.customFontFamilyName,
            customFontFilePath: renderer.customFontFilePath,
            customFontBookmarkData: renderer.customFontBookmarkData,
            useCustomFont: renderer.useCustomFont
        )
        let opacityText = String(format: "%.2f", Double(renderer.backgroundOpacity))
        let cellHeightAdjustment = String(format: "%+.0f%%", Double((renderer.lineHeight - 1.0) * 100))
        let cursorBlink = renderer.cursorBlink ? "true" : "false"

        return """
        macos-background-from-layer = true
        macos-titlebar-proxy-icon = hidden
        shell-integration = zsh
        shell-integration-features = no-cursor
        notify-on-command-finish = always
        notify-on-command-finish-action = no-bell,notify
        notify-on-command-finish-after = 0s
        scrollbar = system
        scrollback-limit = \(defaultScrollbackLimit)
        font-family = \(sanitizedConfigValue(fontFamily))
        font-size = \(fontSizeText)
        adjust-cell-height = \(cellHeightAdjustment)
        background-opacity = \(opacityText)
        cursor-style = \(renderer.cursorStyle.ghosttyValue)
        cursor-style-blink = \(cursorBlink)
        \(theme.ghosttyConfig)
        background = \(theme.ghosttyTerminalBackgroundHex)
        cursor-text = \(theme.ghosttyTerminalBackgroundHex)
        \(overrideConfigText(renderer.activeGhosttyOverrides))
        """
    }

    private static func sanitizedConfigValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func overrideConfigText(_ overrides: [TerminalGhosttyConfigOverride]) -> String {
        guard !overrides.isEmpty else { return "" }
        return overrides
            .map { override in
                let value = normalizedOverrideValue(override)
                return "\(override.key) = \(value)"
            }
            .joined(separator: "\n")
    }

    private static func normalizedOverrideValue(_ override: TerminalGhosttyConfigOverride) -> String {
        let value = sanitizedConfigValue(override.normalizedValue)
        guard override.key == "scrollback-limit" else { return value }
        if let migrated = legacyScrollbackLimits[value] {
            return migrated
        }
        guard let limit = Int(value), limit > 0 else { return defaultScrollbackLimit }
        return String(limit)
    }
}
