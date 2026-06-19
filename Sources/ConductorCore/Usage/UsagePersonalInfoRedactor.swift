import Foundation

public enum UsagePersonalInfoRedactor {
    public static let emailPlaceholder = "Hidden"

    private static let emailRegex: NSRegularExpression? = {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    public static func redactEmail(_ email: String?, isEnabled: Bool) -> String {
        guard let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        guard isEnabled else { return email }
        return emailPlaceholder
    }

    public static func redactEmails(in text: String?, isEnabled: Bool) -> String? {
        guard let text else { return nil }
        guard isEnabled else { return text }
        guard let emailRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return emailRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: emailPlaceholder)
    }
}
