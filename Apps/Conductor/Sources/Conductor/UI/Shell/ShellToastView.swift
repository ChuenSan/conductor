import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ShellToastView: View {
    let toast: ConductorShellToast
    let onAction: (ConductorShellToastAction?) -> Void
    let onDismiss: () -> Void

    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.conductorSystem(size: 12.5, weight: .bold, scale: fontScale))
                .foregroundStyle(toneColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.94))
                        .lineLimit(1)
                    Text(toast.body)
                        .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.76))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle = toast.actionTitle {
                    Button {
                        onAction(toast.action)
                    } label: {
                        Label(actionTitle, systemImage: "arrow.right")
                            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(actionTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Label(L("关闭提示", "Dismiss"), systemImage: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(L("关闭提示", "Dismiss"))
            .accessibilityLabel(L("关闭提示", "Dismiss"))
        }
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConductorTokens.Radius.panel, style: .continuous))
        .frame(width: 374)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.title)
        .accessibilityValue(toast.body)
    }

    private var toneColor: Color {
        switch toast.tone {
        case .info:
            theme.floatingEmphasis
        case .warning:
            Color.orange
        case .error:
            Color.red
        }
    }
}
