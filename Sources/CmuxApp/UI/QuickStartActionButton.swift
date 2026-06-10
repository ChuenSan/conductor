import SwiftUI

struct QuickStartActionButton: View {
    let action: QuickStartAction
    var compact = false

    @State private var hovering = false

    var body: some View {
        Button(action: action.run) {
            HStack(spacing: compact ? 5 : 7) {
                Image(systemName: action.systemImage)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                Text(action.title)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(action.isPrimary ? AppStyle.theme.primarySolidText : AppStyle.textPrimary)
            .padding(.horizontal, compact ? 9 : 12)
            .frame(height: compact ? 26 : 30)
            .background(backgroundShape)
            .overlay(borderShape)
            .scaleEffect(hovering ? 1.035 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.title)
    }

    @ViewBuilder private var backgroundShape: some View {
        let shape = Capsule()
        if action.isPrimary {
            shape.fill(AppStyle.theme.primarySolid)
        } else {
            shape.fill(hovering ? AppStyle.hoverFill : AppStyle.activeFill)
        }
    }

    @ViewBuilder private var borderShape: some View {
        if action.isPrimary {
            Capsule().strokeBorder(Color.white.opacity(AppStyle.theme.isDark ? 0.14 : 0.0), lineWidth: 1)
        } else {
            Capsule().strokeBorder(AppStyle.separator, lineWidth: 1)
        }
    }
}
