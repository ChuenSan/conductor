import SwiftUI

struct QuickStartLaunchPanel: View {
    let title: String
    let subtitle: String
    let primaryActions: [QuickStartAction]
    let secondaryActions: [QuickStartAction]

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            QuickStartIllustration()

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                ForEach(primaryActions) { action in
                    QuickStartActionButton(action: action)
                }
                ForEach(secondaryActions) { action in
                    QuickStartActionButton(action: action, compact: true)
                }
            }
        }
        .frame(maxWidth: 420)
    }
}
