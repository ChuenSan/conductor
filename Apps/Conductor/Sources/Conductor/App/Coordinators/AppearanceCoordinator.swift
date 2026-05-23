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

    mutating func setDensity(_ density: AppearanceDensity) {
        appearance.density = density
    }

    mutating func setChromeClarity(_ chromeClarity: ChromeClarity) {
        appearance.chromeClarity = chromeClarity
    }

    mutating func setFontScale(_ fontScale: AppearanceFontScale) {
        appearance.fontScale = fontScale
    }
}
