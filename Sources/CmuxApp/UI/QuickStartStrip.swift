import SwiftUI

struct QuickStartStrip: View {
    let actions: [QuickStartAction]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(actions) { action in
                QuickStartActionButton(action: action, compact: true)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppStyle.hoverFill.opacity(AppStyle.theme.isDark ? 1 : 0.72))
        )
        .overlay(Capsule().strokeBorder(AppStyle.separator, lineWidth: 1))
        .shadow(color: Color.black.opacity(AppStyle.theme.isDark ? 0.18 : 0.06), radius: 10, y: 4)
    }
}
