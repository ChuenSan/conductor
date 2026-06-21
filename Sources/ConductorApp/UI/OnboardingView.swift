import AppKit
import SwiftUI

enum OnboardingLayout {
    static let dialogSize = CGSize(width: 940, height: 580)
    static let screenshotSize = CGSize(width: 540, height: 405)
    static let screenshotMatPadding: CGFloat = 14
    static var screenshotInnerSize: CGSize {
        CGSize(
            width: screenshotSize.width - screenshotMatPadding * 2,
            height: screenshotSize.height - screenshotMatPadding * 2
        )
    }
    static let contentSpacing: CGFloat = 26
    static let horizontalPadding: CGFloat = 28
    static let screenshotOuterCornerRadius: CGFloat = 16
    static let screenshotInnerCornerRadius: CGFloat = 10
}

struct OnboardingView: View {
    let state: OnboardingPresentationState
    let pages: [OnboardingPage]
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectPage: (Int) -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    private var page: OnboardingPage {
        pages[min(max(0, state.pageIndex), pages.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)

            HStack(spacing: OnboardingLayout.contentSpacing) {
                OnboardingScreenshotView(page: page)
                    .frame(
                        width: OnboardingLayout.screenshotSize.width,
                        height: OnboardingLayout.screenshotSize.height
                    )

                copy
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
            .padding(.top, 18)

            Spacer(minLength: 18)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .frame(width: OnboardingLayout.dialogSize.width, height: OnboardingLayout.dialogSize.height)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppStyle.theme.isDark
                    ? Color(red: 0.075, green: 0.080, blue: 0.095)
                    : Color.white)
                .overlay {
                    ZStack {
                        OnboardingAmbientBackground(accent: page.accent)
                            .opacity(0.45)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppStyle.theme.isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(AppStyle.theme.isDark ? 0.60 : 0.22), radius: 34, y: 18)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(page.accent.color)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(page.accent.color.opacity(0.14)))

                Text(L("认识 Conductor"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
            }

            Spacer()

            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L("跳过介绍"))
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(L(page.eyebrow))
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(page.accent.color)

            Text(L(page.title))
                .font(.system(size: 28, weight: .semibold))
                .lineSpacing(2)
                .foregroundStyle(AppStyle.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L(page.body))
                .font(.system(size: 13.5, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(AppStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(page.beats, id: \.self) { beat in
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(page.accent.color)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(page.accent.color.opacity(0.13)))
                        Text(L(beat))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AppStyle.textPrimary)
                    }
                }
            }
            .padding(.top, 2)
        }
        .animation(Motion.snappy, value: state.pageIndex)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            pageDots

            Spacer()

            Button(action: onPrevious) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(L("上一步"))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.canGoBack ? AppStyle.textPrimary : AppStyle.textTertiary)
                .frame(height: 34)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .disabled(!state.canGoBack)

            Button(action: state.isLastPage ? onDone : onNext) {
                HStack(spacing: 7) {
                    Text(state.isLastPage ? L("开始使用") : L("下一步"))
                    Image(systemName: state.isLastPage ? "arrow.right.circle.fill" : "chevron.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppStyle.theme.primarySolidText)
                .frame(height: 36)
                .padding(.horizontal, 15)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppStyle.theme.primarySolid)
                        .shadow(color: page.accent.color.opacity(AppStyle.theme.isDark ? 0.18 : 0.12), radius: 12, y: 5)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Button {
                    onSelectPage(index)
                } label: {
                    Capsule(style: .continuous)
                        .fill(index == state.pageIndex ? page.accent.color : AppStyle.textTertiary.opacity(0.28))
                        .frame(width: index == state.pageIndex ? 22 : 7, height: 7)
                }
                .buttonStyle(.plain)
                .help(L("切换介绍页"))
            }
        }
        .animation(Motion.snappy, value: state.pageIndex)
    }
}

private struct OnboardingAmbientBackground: View {
    let accent: OnboardingAccent

    var body: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            ZStack {
                RadialGradient(
                    colors: [accent.color.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: maxDim * 0.9)
                RadialGradient(
                    colors: [accent.secondaryColor.opacity(0.12), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: maxDim * 0.75)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OnboardingScreenshotView: View {
    let page: OnboardingPage

    var body: some View {
        let outerShape = RoundedRectangle(
            cornerRadius: OnboardingLayout.screenshotOuterCornerRadius,
            style: .continuous
        )
        let innerShape = RoundedRectangle(
            cornerRadius: OnboardingLayout.screenshotInnerCornerRadius,
            style: .continuous
        )
        return ZStack {
            outerShape
                .fill(AppStyle.theme.isDark
                    ? Color.white.opacity(0.065)
                    : Color(red: 0.988, green: 0.982, blue: 0.970))

            OnboardingAmbientBackground(accent: page.accent)
                .opacity(AppStyle.theme.isDark ? 0.20 : 0.36)
                .clipShape(outerShape)

            if let image = OnboardingScreenshotStore.image(named: page.screenshotName) {
                screenshotImage(image)
                    .clipShape(innerShape)
                    .overlay(
                        innerShape.strokeBorder(
                            AppStyle.theme.isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: .black.opacity(AppStyle.theme.isDark ? 0.30 : 0.11), radius: 14, y: 8)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(page.accent.color)
            }
        }
        .clipShape(outerShape)
        .overlay(outerShape.strokeBorder(AppStyle.theme.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(AppStyle.theme.isDark ? 0.34 : 0.13), radius: 20, y: 11)
        .shadow(color: page.accent.color.opacity(AppStyle.theme.isDark ? 0.10 : 0.08), radius: 26, y: 13)
    }

    private func screenshotImage(_ image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(
                    width: OnboardingLayout.screenshotInnerSize.width,
                    height: OnboardingLayout.screenshotInnerSize.height
                )
                .scaleEffect(page.screenshotFocus.scale)
                .offset(page.screenshotFocus.offset)
                .brightness(AppStyle.theme.isDark ? 0.02 : 0.012)
                .contrast(1.04)
                .saturation(1.04)
        }
        .frame(
            width: OnboardingLayout.screenshotInnerSize.width,
            height: OnboardingLayout.screenshotInnerSize.height
        )
    }
}

private enum OnboardingScreenshotStore {
    static func image(named name: String) -> NSImage? {
        guard let url = appModuleResources.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Onboarding"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}
