import Foundation

/// 取本地化文案。约定：**以中文原文为 key**，英文等翻译放在 `Resources/<locale>.lproj/Localizable.strings`；
/// 缺译时回落到 key 本身（即中文），保证任何语言下都不会显示空白或裸 key 名。
@inline(__always)
func L(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: nil, table: nil)
}

/// 带格式参数的本地化文案（`%@` / `%ld` / `%.1f`…）。多参数请用位置占位符 `%1$@`，便于翻译调序。
@inline(__always)
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Bundle.module.localizedString(forKey: key, value: nil, table: nil), arguments: arguments)
}
