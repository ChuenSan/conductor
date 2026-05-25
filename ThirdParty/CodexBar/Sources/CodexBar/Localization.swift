import Foundation
import CodexBarCore

private func appLanguageDefaults() -> UserDefaults {
    if Bundle.main.bundleIdentifier != nil {
        return .standard
    }
    if UserDefaults.standard.object(forKey: "appLanguage") != nil {
        return .standard
    }
    // Fallback for running outside a .app bundle (swift run / debug builds)
    return UserDefaults(suiteName: "CodexBar") ?? .standard
}

func codexBarLocalizationResourceBundle(
    mainBundle: Bundle = .main,
    bundleName: String = "CodexBar_CodexBar") -> Bundle
{
    guard mainBundle.bundleURL.pathExtension == "app" else {
        return Bundle.module
    }

    if let url = mainBundle.url(forResource: bundleName, withExtension: "bundle"),
       let bundle = Bundle(url: url)
    {
        return bundle
    }

    if let resourceURL = mainBundle.resourceURL?.absoluteURL,
       let bundle = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle"))
    {
        return bundle
    }

    return mainBundle
}

private func localizedBundle() -> Bundle {
    let resourceBundle = codexBarLocalizationResourceBundle()
    let language = activeAppLanguageIdentifier()
    if !language.isEmpty {
        if let bundle = lprojBundle(named: language, in: resourceBundle) {
            return bundle
        }
    } else {
        // System mode: follow macOS language preferences
        if let preferred = resourceBundle.preferredLocalizations.first,
           let bundle = lprojBundle(named: preferred, in: resourceBundle)
        {
            return bundle
        }
    }
    // Fallback to en.lproj
    if let path = resourceBundle.path(forResource: "en", ofType: "lproj"),
       let bundle = Bundle(path: path)
    {
        return bundle
    }
    return resourceBundle
}

private func activeAppLanguageIdentifier() -> String {
    if ConductorUsageFeature.hasHostLanguageIdentifierOverride {
        return ConductorUsageFeature.currentHostLanguageIdentifier ?? ""
    }
    return appLanguageDefaults().string(forKey: "appLanguage") ?? ""
}

private func lprojBundle(named language: String, in resourceBundle: Bundle) -> Bundle? {
    let candidates = [language, language.lowercased()]
    for candidate in candidates where !candidate.isEmpty {
        if let path = resourceBundle.path(forResource: candidate, ofType: "lproj"),
           let bundle = Bundle(path: path)
        {
            return bundle
        }
    }
    return nil
}

func L(_ key: String) -> String {
    let resourceBundle = codexBarLocalizationResourceBundle()
    return CodexBarDisplayBrand.userFacing(
        codexBarLocalizedString(key, bundle: localizedBundle(), resourceBundle: resourceBundle))
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}

func codexBarLocalizedDisplayText(_ text: String) -> String {
    let exact = L(text)
    if exact != text {
        return exact
    }

    let language = activeAppLanguageIdentifier().lowercased()
    guard language.hasPrefix("zh") else {
        return CodexBarDisplayBrand.userFacing(text)
    }

    var localized = CodexBarDisplayBrand.userFacing(text)
    let exactReplacements: [String: String] = [
        "Add": "添加",
        "Auto": "自动",
        "Automatic": "自动",
        "Label": "标签",
        "Manual": "手动",
        "Open token file": "打开 Token 文件",
        "Org ID (optional)": "组织 ID（可选）",
        "Refresh": "刷新",
        "Refresh organizations": "刷新组织",
        "Reload": "重新加载",
        "Remove": "移除",
        "No organizations loaded. Click Refresh after setting your API key.": "尚未加载组织。设置 API 密钥后点击刷新。",
        "No token accounts yet.": "尚无 Token 账户。",
        "Optional organization ID for accounts linked to multiple Anthropic organizations.": "关联多个 Anthropic 组织的账户可填写组织 ID。",
        "Lasts until reset": "持续到重置",
        "On pace": "节奏正常",
        "Credits unavailable; keep Codex running to refresh.": "额度暂不可用；保持 Codex 运行以刷新。",
        "Hover a bar for details": "悬停柱状条查看详情",
        "Usage remaining": "剩余额度",
        "Usage used": "已用额度",
        "API key limit": "API Key 限额",
        "Copied": "已复制",
        "Copy error": "复制错误",
        "Extra usage spent": "额外用量花费",
        "Credits remaining": "剩余额度",
        "Reading usage": "正在读取用量",
        "Estimated from local Codex logs for the selected account.": "根据所选账户的本地日志估算。",
        "Reported by AWS Cost Explorer; daily billing data can lag.": "由 AWS Cost Explorer 报告；每日账单数据可能延迟。",
        "Latest billing day": "最近账单日",
        "API spend": "API 花费",
        "Quota usage": "配额用量",
        "Extra usage": "额外用量",
        "Balance": "余额",
        "This month": "本月",
        "Updated just now": "刚刚更新",
        "Paid": "付费",
        "Free": "免费",
        "Not fetched yet": "尚未获取",
        "Refreshing...": "正在刷新...",
    ]
    if let replacement = exactReplacements[localized] {
        return replacement
    }

    if localized.hasSuffix("% left") {
        localized = localized.replacingOccurrences(of: "% left", with: "% 剩余")
    }
    if localized.hasSuffix("% used") {
        localized = localized.replacingOccurrences(of: "% used", with: "% 已用")
    }
    if localized.hasSuffix(" left") {
        localized = localized.replacingOccurrences(of: " left", with: " 剩余")
    }
    if localized.hasSuffix(" tokens") {
        localized = localized.replacingOccurrences(of: " tokens", with: " Token")
    }
    if localized.hasPrefix("Updated ") {
        localized = "更新于 " + String(localized.dropFirst("Updated ".count))
    }
    if localized.hasPrefix("Resets in ") {
        localized = "还有 " + String(localized.dropFirst("Resets in ".count)) + " 重置"
    } else if localized.hasPrefix("Resets at ") {
        localized = "重置时间 " + String(localized.dropFirst("Resets at ".count))
    } else if localized.hasPrefix("Resets ") {
        localized = "重置 " + String(localized.dropFirst("Resets ".count))
    }
    if localized.hasPrefix("Lasts until ") {
        localized = "持续到 " + String(localized.dropFirst("Lasts until ".count))
    }
    if localized.hasPrefix("Today:") {
        localized = localized.replacingOccurrences(of: "Today:", with: "今日：")
    }
    if localized.hasPrefix("This month:") {
        localized = localized.replacingOccurrences(of: "This month:", with: "本月：")
    }
    if localized.hasPrefix("Balance:") {
        localized = localized.replacingOccurrences(of: "Balance:", with: "余额：")
    }
    if localized.hasPrefix("Last 30 days:") {
        localized = localized.replacingOccurrences(of: "Last 30 days:", with: "近 30 天：")
    } else if localized.hasPrefix("Last "), localized.contains(" days:") {
        localized = localized.replacingOccurrences(of: "Last ", with: "近 ")
        localized = localized.replacingOccurrences(of: " days:", with: " 天：")
    }
    if localized.hasPrefix("Latest billing day (") {
        localized = localized.replacingOccurrences(of: "Latest billing day", with: "最近账单日")
    }
    return localized
}

func codexBarLocalizedString(_ key: String, bundle: Bundle, resourceBundle: Bundle) -> String {
    let value = bundle.localizedString(forKey: key, value: nil, table: nil)
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, value != key {
        return value
    }

    guard bundle.bundleURL.lastPathComponent != "en.lproj",
          let englishBundle = lprojBundle(named: "en", in: resourceBundle)
    else {
        return CodexBarDisplayBrand.userFacing(trimmed.isEmpty ? key : value)
    }

    let fallback = englishBundle.localizedString(forKey: key, value: nil, table: nil)
    let resolved = fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? key : fallback
    return CodexBarDisplayBrand.userFacing(resolved)
}
