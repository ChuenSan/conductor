import SwiftUI

/// 带占位符的多行提交信息输入框，配 conductor 卡片底色。
struct GitCommitEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.hoverFill)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(AppStyle.textTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AppStyle.separator, lineWidth: 1))
    }
}
