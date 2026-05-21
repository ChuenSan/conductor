import CoreGraphics
import Foundation

enum TerminalCursorStyle: String, CaseIterable, Codable, Identifiable {
    case block
    case blockHollow
    case bar
    case underline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block: ConductorLocalization.text(zh: "块", en: "Block")
        case .blockHollow: ConductorLocalization.text(zh: "空心块", en: "Hollow")
        case .bar: ConductorLocalization.text(zh: "竖线", en: "Bar")
        case .underline: ConductorLocalization.text(zh: "下划线", en: "Underline")
        }
    }

    var ghosttyValue: String {
        switch self {
        case .block: "block"
        case .blockHollow: "block_hollow"
        case .bar: "bar"
        case .underline: "underline"
        }
    }
}

struct TerminalProxyPreferences: Codable, Equatable {
    var enabled: Bool
    var httpProxy: String
    var httpsProxy: String
    var allProxy: String
    var noProxy: String

    init(
        enabled: Bool = false,
        httpProxy: String = "",
        httpsProxy: String = "",
        allProxy: String = "",
        noProxy: String = "localhost,127.0.0.1,::1"
    ) {
        self.enabled = enabled
        self.httpProxy = httpProxy
        self.httpsProxy = httpsProxy
        self.allProxy = allProxy
        self.noProxy = noProxy
    }

    var environment: [String: String] {
        guard enabled else { return [:] }
        var values: [String: String] = [:]
        add(httpProxy, as: "HTTP_PROXY", to: &values)
        add(httpProxy, as: "http_proxy", to: &values)
        add(httpsProxy, as: "HTTPS_PROXY", to: &values)
        add(httpsProxy, as: "https_proxy", to: &values)
        add(allProxy, as: "ALL_PROXY", to: &values)
        add(allProxy, as: "all_proxy", to: &values)
        add(noProxy, as: "NO_PROXY", to: &values)
        add(noProxy, as: "no_proxy", to: &values)
        return values
    }

    var hasProxyValue: Bool {
        !httpProxy.trimmedForTerminalEnvironment.isEmpty ||
            !httpsProxy.trimmedForTerminalEnvironment.isEmpty ||
            !allProxy.trimmedForTerminalEnvironment.isEmpty
    }

    var statusTitle: String {
        guard enabled else {
            return ConductorLocalization.text(zh: "未启用", en: "Disabled")
        }
        return hasProxyValue
            ? ConductorLocalization.text(zh: "已启用，新终端生效", en: "Enabled for new terminals")
            : ConductorLocalization.text(zh: "已启用，但还没有代理地址", en: "Enabled, no proxy address yet")
    }

    private func add(_ value: String, as key: String, to values: inout [String: String]) {
        let trimmed = value.trimmedForTerminalEnvironment
        guard !trimmed.isEmpty else { return }
        values[key] = trimmed
    }
}

struct TerminalGhosttyConfigOverride: Codable, Equatable, Identifiable {
    var key: String
    var value: String
    var enabled: Bool

    var id: String { key }

    init(key: String, value: String = "", enabled: Bool = false) {
        self.key = key
        self.value = value
        self.enabled = enabled
    }

    var normalizedValue: String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TerminalRendererPreferences: Codable, Equatable {
    var fontPreset: TerminalFontPreset
    var useCustomFont: Bool
    var customFontFamilyName: String?
    var customFontFilePath: String?
    var customFontBookmarkData: Data?
    var lineHeight: CGFloat
    var backgroundOpacity: CGFloat
    var cursorStyle: TerminalCursorStyle
    var cursorBlink: Bool
    var shellIntegrationEnabled: Bool
    var proxy: TerminalProxyPreferences
    var ghosttyOverrides: [TerminalGhosttyConfigOverride]

    init(
        fontPreset: TerminalFontPreset = .menlo,
        useCustomFont: Bool = false,
        customFontFamilyName: String? = nil,
        customFontFilePath: String? = nil,
        customFontBookmarkData: Data? = nil,
        lineHeight: CGFloat = 1.0,
        backgroundOpacity: CGFloat = 1.0,
        cursorStyle: TerminalCursorStyle = .block,
        cursorBlink: Bool = true,
        shellIntegrationEnabled: Bool = true,
        proxy: TerminalProxyPreferences = TerminalProxyPreferences(),
        ghosttyOverrides: [TerminalGhosttyConfigOverride] = []
    ) {
        self.fontPreset = fontPreset
        self.useCustomFont = useCustomFont
        self.customFontFamilyName = customFontFamilyName
        self.customFontFilePath = customFontFilePath
        self.customFontBookmarkData = customFontBookmarkData
        self.lineHeight = min(max(lineHeight, 0.80), 1.50)
        self.backgroundOpacity = min(max(backgroundOpacity, 0.20), 1.0)
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.shellIntegrationEnabled = true
        self.proxy = proxy
        self.ghosttyOverrides = Self.normalizedOverrides(ghosttyOverrides)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontPreset = try container.decodeIfPresent(TerminalFontPreset.self, forKey: .fontPreset) ?? .menlo
        self.useCustomFont = try container.decodeIfPresent(Bool.self, forKey: .useCustomFont) ?? false
        self.customFontFamilyName = try container.decodeIfPresent(String.self, forKey: .customFontFamilyName)
        self.customFontFilePath = try container.decodeIfPresent(String.self, forKey: .customFontFilePath)
        self.customFontBookmarkData = try container.decodeIfPresent(Data.self, forKey: .customFontBookmarkData)
        let decodedLineHeight = try container.decodeIfPresent(CGFloat.self, forKey: .lineHeight) ?? 1.0
        let decodedOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .backgroundOpacity) ?? 1.0
        self.lineHeight = min(max(decodedLineHeight, 0.80), 1.50)
        self.backgroundOpacity = min(max(decodedOpacity, 0.20), 1.0)
        self.cursorStyle = try container.decodeIfPresent(TerminalCursorStyle.self, forKey: .cursorStyle) ?? .block
        self.cursorBlink = try container.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? true
        self.shellIntegrationEnabled = true
        self.proxy = try container.decodeIfPresent(TerminalProxyPreferences.self, forKey: .proxy) ?? TerminalProxyPreferences()
        self.ghosttyOverrides = Self.normalizedOverrides(
            try container.decodeIfPresent([TerminalGhosttyConfigOverride].self, forKey: .ghosttyOverrides) ?? []
        )
    }

    var effectiveFontFamilyName: String {
        TerminalFontLibrary.resolvedFamilyName(
            preset: fontPreset,
            customFamilyName: customFontFamilyName,
            customFontFilePath: customFontFilePath,
            customFontBookmarkData: customFontBookmarkData,
            useCustomFont: useCustomFont
        )
    }

    var selectedFontStatusTitle: String {
        if useCustomFont {
            guard let customFontFamilyName, !customFontFamilyName.isEmpty else {
                return ConductorLocalization.text(zh: "未导入自定义字体", en: "No custom font imported")
            }
            return TerminalFontAvailability.isFamilyInstalled(customFontFamilyName)
                ? ConductorLocalization.text(zh: "自定义：\(customFontFamilyName)", en: "Custom: \(customFontFamilyName)")
                : ConductorLocalization.text(zh: "自定义字体失效，回退到 Menlo", en: "Custom font unavailable, falls back to Menlo")
        }
        return TerminalFontAvailability.availabilityLabel(for: fontPreset)
    }

    func ghosttyOverride(for key: String) -> TerminalGhosttyConfigOverride {
        ghosttyOverrides.first { $0.key == key } ?? TerminalGhosttyConfigOverride(key: key)
    }

    func activeGhosttyOverrideValue(for key: String) -> String? {
        let override = ghosttyOverride(for: key)
        guard override.enabled else { return nil }
        let value = override.normalizedValue
        return value.isEmpty ? nil : value
    }

    var activeGhosttyOverrides: [TerminalGhosttyConfigOverride] {
        Self.normalizedOverrides(ghosttyOverrides)
            .filter { override in
                override.enabled &&
                    TerminalGhosttyConfigCatalog.knownKeySet.contains(override.key) &&
                    !override.normalizedValue.isEmpty
            }
    }

    static func normalizedOverrides(_ overrides: [TerminalGhosttyConfigOverride]) -> [TerminalGhosttyConfigOverride] {
        var byKey: [String: TerminalGhosttyConfigOverride] = [:]
        for override in overrides {
            guard TerminalGhosttyConfigCatalog.knownKeySet.contains(override.key) else { continue }
            byKey[override.key] = override
        }
        return byKey.values.sorted { $0.key < $1.key }
    }

    private enum CodingKeys: String, CodingKey {
        case fontPreset
        case useCustomFont
        case customFontFamilyName
        case customFontFilePath
        case customFontBookmarkData
        case lineHeight
        case backgroundOpacity
        case cursorStyle
        case cursorBlink
        case shellIntegrationEnabled
        case proxy
        case ghosttyOverrides
    }
}

enum TerminalAppearanceRuntime {
    nonisolated(unsafe) static var renderer = TerminalRendererPreferences()

    static func apply(_ appearance: AppearancePreferences) {
        renderer = appearance.terminalRenderer
        TerminalFontLibrary.registerCustomFontIfNeeded(
            path: renderer.customFontFilePath,
            bookmarkData: renderer.customFontBookmarkData
        )
    }
}

private extension String {
    var trimmedForTerminalEnvironment: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
