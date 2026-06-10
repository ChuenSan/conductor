import Foundation

/// 应用语言切换：通过 UserDefaults 的 `AppleLanguages` 覆盖本应用的语言协商，重启后生效。
/// 选项另存一份到 `choiceKey`，用于区分「用户显式选择」与「跟随系统」（AppleLanguages
/// 直接读会拿到系统继承值，无法区分两者）。
enum AppLanguage {
    static let system = "system"
    static let simplifiedChinese = "zh-Hans"
    static let english = "en"

    private static let appleLanguagesKey = "AppleLanguages"
    private static let choiceKey = "cmux.languageChoice"

    /// 当前选择（无显式选择 → 跟随系统）。
    static var current: String {
        UserDefaults.standard.string(forKey: choiceKey) ?? system
    }

    /// 应用选择并持久化；重启应用后 Bundle 按新语言解析。
    static func apply(_ choice: String) {
        let defaults = UserDefaults.standard
        switch choice {
        case simplifiedChinese, english:
            defaults.set([choice], forKey: appleLanguagesKey)
            defaults.set(choice, forKey: choiceKey)
        default:
            defaults.removeObject(forKey: appleLanguagesKey)
            defaults.removeObject(forKey: choiceKey)
        }
    }
}
