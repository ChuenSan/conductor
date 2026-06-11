import SwiftUI

/// 「AI 正在思考」动效：小转圈（旋转的圆弧 spinner）。
/// 数据源是 coordinator.thinkingPanes（视口文本变化 + CPU 占用推断）。
struct ThinkingIndicator: View {
    var size: CGFloat = 7
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(AppStyle.accent, style: StrokeStyle(lineWidth: max(1.2, size / 5), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
            .help(L("AI 正在思考"))
            .accessibilityLabel(L("AI 正在思考"))
    }
}
