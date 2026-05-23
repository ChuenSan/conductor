import SwiftUI

struct ConductorCommandButton: View {
    let state: ConductorControlState
    var fillsWidth = false
    let action: () -> Void

    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        Button {
            guard state.isEnabled else { return }
            action()
        } label: {
            Label {
                if let title = state.title {
                    Text(title)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: state.systemImage)
            }
            .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
            .frame(minHeight: 28)
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.98))
        .disabled(!state.isEnabled)
        .help(state.tooltip)
        .accessibilityLabel(Text(state.accessibilityLabel))
        .foregroundStyle(state.isEnabled ? theme.shellChromeText.opacity(0.88) : theme.shellChromeTextMuted.opacity(0.45))
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(state.isActive ? theme.floatingSelectedFill.opacity(0.64) : theme.floatingControlFill.opacity(0.24))
        }
    }
}
