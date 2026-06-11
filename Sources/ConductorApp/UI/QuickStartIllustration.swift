import SwiftUI

struct QuickStartIllustration: View {
    var compact = false

    var body: some View {
        ZStack {
            roundedTerminal
                .offset(x: compact ? -10 : -14, y: compact ? 4 : 6)
            orbitingTiles
            sparkPath
        }
        .frame(width: compact ? 72 : 108, height: compact ? 58 : 82)
        .accessibilityHidden(true)
    }

    private var roundedTerminal: some View {
        RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
            .fill(AppStyle.elevated.opacity(AppStyle.theme.isDark ? 0.38 : 0.74))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                    .strokeBorder(AppStyle.separator, lineWidth: 1)
            )
            .frame(width: compact ? 52 : 74, height: compact ? 38 : 52)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    Circle().fill(AppStyle.accent.opacity(0.95)).frame(width: 4, height: 4)
                    Circle().fill(AppStyle.textTertiary.opacity(0.55)).frame(width: 4, height: 4)
                    Circle().fill(AppStyle.textTertiary.opacity(0.35)).frame(width: 4, height: 4)
                }
                .padding(.top, 8)
                .padding(.leading, 9)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 5) {
                    Text(">")
                        .font(.system(size: compact ? 11 : 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppStyle.accent)
                    Capsule()
                        .fill(AppStyle.textTertiary.opacity(0.38))
                        .frame(width: compact ? 15 : 22, height: 3)
                }
                .padding(.leading, 10)
                .padding(.bottom, 10)
            }
            .rotationEffect(.degrees(-4))
    }

    private var orbitingTiles: some View {
        ZStack {
            tile("rectangle.split.2x1", x: compact ? 24 : 35, y: compact ? -17 : -25, angle: 7)
            tile("sparkles", x: compact ? 30 : 43, y: compact ? 16 : 22, angle: -11)
            tile("command", x: compact ? -31 : -45, y: compact ? -12 : -16, angle: 9)
        }
    }

    private func tile(_ symbol: String, x: CGFloat, y: CGFloat, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
            .fill(AppStyle.hoverFill)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: compact ? 10 : 13, weight: .semibold))
                    .foregroundStyle(symbol == "sparkles" ? AppStyle.accent : AppStyle.textSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .strokeBorder(AppStyle.separator, lineWidth: 1)
            )
            .frame(width: compact ? 25 : 34, height: compact ? 23 : 30)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
    }

    private var sparkPath: some View {
        Path { path in
            path.move(to: CGPoint(x: compact ? 18 : 30, y: compact ? 44 : 62))
            path.addCurve(
                to: CGPoint(x: compact ? 55 : 87, y: compact ? 13 : 16),
                control1: CGPoint(x: compact ? 32 : 48, y: compact ? 55 : 76),
                control2: CGPoint(x: compact ? 43 : 67, y: compact ? -2 : -4)
            )
        }
        .stroke(
            AppStyle.accent.opacity(AppStyle.theme.isDark ? 0.42 : 0.36),
            style: StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, dash: [4, 5])
        )
    }
}
