import AppKit

enum TerminalFontAvailability {
    nonisolated(unsafe) private static var cachedFamilyNames: Set<String>?

    static var installedFamilyNames: Set<String> {
        if let cachedFamilyNames {
            return cachedFamilyNames
        }
        let families = Set(NSFontManager.shared.availableFontFamilies)
        cachedFamilyNames = families
        return families
    }

    static func refresh() {
        cachedFamilyNames = Set(NSFontManager.shared.availableFontFamilies)
    }

    static func isInstalled(_ preset: TerminalFontPreset) -> Bool {
        let installed = installedFamilyNames
        return preset.candidateFamilyNames.contains { installed.contains($0) }
    }

    static func installedCandidate(for preset: TerminalFontPreset) -> String? {
        let installed = installedFamilyNames
        return preset.candidateFamilyNames.first { installed.contains($0) }
    }

    static func isFamilyInstalled(_ familyName: String?) -> Bool {
        guard let familyName, !familyName.isEmpty else { return false }
        return installedFamilyNames.contains(familyName)
    }

    static func availabilityLabel(for preset: TerminalFontPreset) -> String {
        if let family = installedCandidate(for: preset) {
            return ConductorLocalization.text(zh: "已安装：\(family)", en: "Installed: \(family)")
        }
        return ConductorLocalization.text(zh: "未安装，当前自动回退到 Menlo", en: "Missing; currently falls back to Menlo")
    }
}
