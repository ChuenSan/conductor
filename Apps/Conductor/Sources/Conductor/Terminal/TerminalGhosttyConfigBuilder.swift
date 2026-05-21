import Foundation

struct TerminalGhosttyConfigBuilder {
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
        shell-integration = detect
        shell-integration-features = no-cursor
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
            .map { "\($0.key) = \(sanitizedConfigValue($0.normalizedValue))" }
            .joined(separator: "\n")
    }
}
