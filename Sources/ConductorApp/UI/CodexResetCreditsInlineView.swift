import ConductorCore
import SwiftUI

enum CodexResetCreditsDisplay {
    static func countText(_ snapshot: CodexRateLimitResetCreditsSnapshot?) -> String {
        guard let snapshot else { return L("未提供") }
        return L("%ld 张可用", snapshot.availableCount)
    }

    static func nextExpiryText(
        _ snapshot: CodexRateLimitResetCreditsSnapshot,
        showAbsolute: Bool) -> String?
    {
        guard let expiresAt = snapshot.nextExpiringAvailableCredit?.expiresAt else { return nil }
        return UsageFormatting.resetText(expiresAt, showAbsolute: showAbsolute)
    }

    static func detailText(
        _ snapshot: CodexRateLimitResetCreditsSnapshot,
        showAbsolute: Bool) -> String
    {
        var parts = [L("%ld 张可用", snapshot.availableCount)]
        if let expiry = nextExpiryText(snapshot, showAbsolute: showAbsolute) {
            parts.append(L("下一张过期：%@", expiry))
        }
        parts.append(L("更新：%@", UsageFormatting.agoText(snapshot.updatedAt)))
        return parts.joined(separator: " · ")
    }

    static func tooltip(
        _ snapshot: CodexRateLimitResetCreditsSnapshot,
        showAbsolute: Bool) -> String
    {
        var lines = [L("限额重置券"), detailText(snapshot, showAbsolute: showAbsolute)]
        let latest = snapshot.credits.prefix(3).map { credit in
            let title = credit.title?.isEmpty == false ? credit.title! : credit.resetType
            return "\(title): \(statusText(credit.status))"
        }
        lines.append(contentsOf: latest)
        return lines.joined(separator: "\n")
    }

    static func statusText(_ status: CodexRateLimitResetCreditStatus) -> String {
        switch status {
        case .available:
            return L("可用券")
        case .redeeming:
            return L("使用中的券")
        case .redeemed:
            return L("已使用的券")
        case .expired:
            return L("已过期的券")
        case let .unknown(value):
            return value
        }
    }
}

struct CodexResetCreditsInlineView: View {
    let snapshot: CodexRateLimitResetCreditsSnapshot
    var compact = false

    @ObservedObject private var configStore = ConfigStore.shared

    private var nextExpiry: String? {
        CodexResetCreditsDisplay.nextExpiryText(
            snapshot,
            showAbsolute: configStore.config.usage.resetTimesShowAbsolute)
    }

    private var availableCredits: [CodexRateLimitResetCredit] {
        snapshot.credits.filter { $0.status == .available }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 14)
                Text(L("%ld 张可用", snapshot.availableCount))
                    .font(.system(size: compact ? 10.6 : 11.2, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textPrimary)
                if !compact {
                    Text(L("限额重置券"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let nextExpiry {
                Text(L("下一张过期：%@", nextExpiry))
                    .font(.system(size: compact ? 9.5 : 9.8, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }

            if !compact, !availableCredits.isEmpty {
                let preview = availableCredits.prefix(3).map { credit in
                    credit.title?.isEmpty == false ? credit.title! : credit.resetType
                }
                Text(preview.joined(separator: " · "))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("限额重置券"))
        .accessibilityValue(CodexResetCreditsDisplay.detailText(
            snapshot,
            showAbsolute: configStore.config.usage.resetTimesShowAbsolute))
        .help(CodexResetCreditsDisplay.tooltip(
            snapshot,
            showAbsolute: configStore.config.usage.resetTimesShowAbsolute))
    }
}
