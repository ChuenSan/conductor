import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private enum ConductorImageZoomMode: String, CaseIterable, Identifiable {
    case fit
    case actual
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit:
            L("适应", "Fit")
        case .actual:
            L("实际", "Actual")
        case .custom:
            L("缩放", "Zoom")
        }
    }

    var systemImage: String {
        switch self {
        case .fit:
            "arrow.up.left.and.arrow.down.right"
        case .actual:
            "1.magnifyingglass"
        case .custom:
            "magnifyingglass"
        }
    }
}

struct ConductorImageWorkspaceView: View {
    let url: URL
    let theme: TerminalTheme
    var isActive = true

    @StateObject private var imageLoader = ConductorAsyncImageLoader()
    @State private var zoomMode: ConductorImageZoomMode = .fit
    @State private var zoomScale: CGFloat = 1
    @State private var statusMessage: String?
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        VStack(spacing: 0) {
            imageToolbar
            content
        }
        .background(theme.terminalBackground)
        .task(id: url) {
            imageLoader.load(url: url)
            statusMessage = nil
        }
        .background {
            ConductorKeyboardShortcutBridge(autofocus: isActive) { event in
                handleKeyboardShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
    }

    private var imageToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let image = imageLoader.image {
                    statusLabel(systemImage: "photo", title: dimensions(for: image))
                }

                Picker("", selection: $zoomMode) {
                    ForEach(ConductorImageZoomMode.allCases) { mode in
                        Image(systemName: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 104)
                .help(L("图片缩放模式 Cmd-0/Cmd-1/Cmd-+", "Image Zoom Mode Cmd-0/Cmd-1/Cmd-+"))

                Slider(value: $zoomScale, in: 0.1...4, step: 0.05)
                    .frame(width: 112)
                    .disabled(zoomMode != .custom)
                    .help(L("缩放比例", "Zoom Scale"))

                Text("\(Int(effectiveZoomPercent))%")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.52))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    copy(url.path)
                } label: {
                    Label(L("复制路径 Cmd-Opt-C", "Copy Path Cmd-Opt-C"), systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("复制路径 Cmd-Opt-C", "Copy Path Cmd-Opt-C"))
                .accessibilityLabel(L("复制路径 Cmd-Opt-C", "Copy Path Cmd-Opt-C"))
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(L("系统应用打开 Cmd-O", "Open in System App Cmd-O"), systemImage: "arrow.up.right.square")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("系统应用打开 Cmd-O", "Open in System App Cmd-O"))
                .accessibilityLabel(L("系统应用打开 Cmd-O", "Open in System App Cmd-O"))
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label(L("在 Finder 中显示 Cmd-Opt-R", "Reveal in Finder Cmd-Opt-R"), systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("在 Finder 中显示 Cmd-Opt-R", "Reveal in Finder Cmd-Opt-R"))
                .accessibilityLabel(L("在 Finder 中显示 Cmd-Opt-R", "Reveal in Finder Cmd-Opt-R"))
                .keyboardShortcut("r", modifiers: [.command, .option])
            }
            .padding(.horizontal, 12)
            .frame(height: 33)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if let image = imageLoader.image {
            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displaySize(for: image, in: proxy.size).width, height: displaySize(for: image, in: proxy.size).height)
                        .padding(28)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                }
                .background(theme.terminalBackground)
            }
        } else {
            ContentUnavailableView {
                Label(
                    imageLoader.isLoading ? L("正在读取图片", "Loading Image") : L("图片无法读取", "Image Could Not Load"),
                    systemImage: imageLoader.isLoading ? "hourglass" : "photo"
                )
            } description: {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .overlay(alignment: .topTrailing) {
                if imageLoader.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(14)
                }
            }
            .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.62))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var effectiveZoomPercent: CGFloat {
        switch zoomMode {
        case .fit:
            100
        case .actual:
            100
        case .custom:
            zoomScale * 100
        }
    }

    private func displaySize(for image: NSImage, in container: CGSize) -> CGSize {
        let base = normalizedSize(for: image)
        switch zoomMode {
        case .fit:
            let available = CGSize(width: max(1, container.width - 56), height: max(1, container.height - 56))
            let scale = min(available.width / base.width, available.height / base.height, 1)
            return CGSize(width: max(1, base.width * scale), height: max(1, base.height * scale))
        case .actual:
            return base
        case .custom:
            return CGSize(width: max(1, base.width * zoomScale), height: max(1, base.height * zoomScale))
        }
    }

    private func normalizedSize(for image: NSImage) -> CGSize {
        let representation = image.representations.max { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }
        if let representation, representation.pixelsWide > 0, representation.pixelsHigh > 0 {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return CGSize(width: max(1, image.size.width), height: max(1, image.size.height))
    }

    private func dimensions(for image: NSImage) -> String {
        let size = normalizedSize(for: image)
        return "\(Int(size.width)) x \(Int(size.height))"
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = L("已复制路径", "Path copied")
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch characters {
            case "0":
                zoomMode = .fit
                statusMessage = L("适应窗口", "Fit to window")
                return true
            case "1":
                zoomMode = .actual
                statusMessage = L("实际大小", "Actual size")
                return true
            case "+", "=":
                zoomIn()
                return true
            case "-":
                zoomOut()
                return true
            case "c" where flags.contains(.option):
                copy(url.path)
                return true
            case "o":
                NSWorkspace.shared.open(url)
                return true
            case "r" where flags.contains(.option):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return true
            default:
                break
            }
        }

        if characters == "+" || characters == "=" {
            zoomIn()
            return true
        }
        if characters == "-" {
            zoomOut()
            return true
        }
        return false
    }

    private func zoomIn() {
        zoomMode = .custom
        zoomScale = min(4, zoomScale + 0.1)
        statusMessage = L("放大到 \(Int(zoomScale * 100))%", "Zoom \(Int(zoomScale * 100))%")
    }

    private func zoomOut() {
        zoomMode = .custom
        zoomScale = max(0.1, zoomScale - 0.1)
        statusMessage = L("缩小到 \(Int(zoomScale * 100))%", "Zoom \(Int(zoomScale * 100))%")
    }

    private func statusLabel(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
        .foregroundStyle(theme.shellChromeText.opacity(0.64))
        .frame(height: 22)
    }

}
