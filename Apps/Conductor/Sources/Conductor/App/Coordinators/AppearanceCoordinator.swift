import Foundation

struct AppearanceCoordinator: Equatable {
    private(set) var appearance: AppearancePreferences

    init(appearance: AppearancePreferences) {
        self.appearance = appearance
    }

    mutating func setTerminalFontSize(_ terminalFontSize: CGFloat) {
        let clamped = AppearancePreferences.clampedTerminalFontSize(terminalFontSize)
        appearance.terminalFontSize = (clamped * 2).rounded() / 2
    }

    mutating func setTerminalBackgroundOpacity(_ opacity: CGFloat) {
        appearance.terminalRenderer.backgroundOpacity = Self.roundedTerminalBackgroundOpacity(opacity)
    }

    mutating func setTerminalBackgroundBlur(_ enabled: Bool) {
        setTerminalRendererOverride(key: "background-blur", value: enabled ? "true" : "false", enabled: true)
    }

    mutating func setTerminalBackgroundImageURL(_ imageURL: URL?) {
        guard let imageURL else {
            setTerminalRendererOverride(key: "background-image", value: "", enabled: false)
            return
        }
        setTerminalRendererOverride(key: "background-image", value: imageURL.standardizedFileURL.path, enabled: true)
    }

    mutating func setTerminalBackgroundImageMode(_ imageMode: String) {
        let value = imageMode.trimmingCharacters(in: .whitespacesAndNewlines)
        setTerminalRendererOverride(key: "background-image-fit", value: value, enabled: !value.isEmpty)
    }

    mutating func setDensity(_ density: AppearanceDensity) {
        appearance.density = density
    }

    mutating func setChromeClarity(_ chromeClarity: ChromeClarity) {
        appearance.chromeClarity = chromeClarity
    }

    mutating func setFontScale(_ fontScale: AppearanceFontScale) {
        appearance.fontScale = fontScale
    }

    static func roundedTerminalBackgroundOpacity(_ opacity: CGFloat) -> CGFloat {
        (min(max(opacity, 0.20), 1.0) * 100).rounded() / 100
    }

    private mutating func setTerminalRendererOverride(key: String, value: String, enabled: Bool) {
        guard TerminalGhosttyConfigCatalog.knownKeySet.contains(key) else { return }
        var overrides = appearance.terminalRenderer.ghosttyOverrides
        if let index = overrides.firstIndex(where: { $0.key == key }) {
            overrides[index].value = value
            overrides[index].enabled = enabled
        } else {
            overrides.append(TerminalGhosttyConfigOverride(key: key, value: value, enabled: enabled))
        }
        appearance.terminalRenderer.ghosttyOverrides = TerminalRendererPreferences.normalizedOverrides(overrides)
    }
}
