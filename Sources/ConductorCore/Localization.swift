import Foundation

/// ConductorCore 内部本地化助手。约定：**以中文原文为 key**，缺译回落中文。
@inline(__always)
func L(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: nil, table: nil)
}

/// 带格式参数版本。多参数用位置占位符 `%1$@`，便于翻译调序。
@inline(__always)
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Bundle.module.localizedString(forKey: key, value: nil, table: nil), arguments: arguments)
}
