import AppKit
import SwiftUI

@main
struct GhosttySurfaceValidationApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let harness = ValidationHarness()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = ValidationShellView(harness: harness)
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ghostty Surface Validation"
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        if ProcessInfo.processInfo.environment["GHOSTTY_VALIDATION_AUTORUN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [harness] in
                harness.runAutomatedValidation()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        GhosttyRuntime.shared.setAppFocus(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        GhosttyRuntime.shared.setAppFocus(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        harness.closeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct ValidationShellView: View {
    @ObservedObject var harness: ValidationHarness

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                toolbar
                splitArea
                    .background(harness.theme.shellBackground)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(harness.theme.shellBackground)
        .tint(harness.theme.accent)
    }

    @ViewBuilder
    private var splitArea: some View {
        if harness.splitAxis == .horizontal {
            HStack(spacing: 1) {
                paneViews
            }
        } else {
            VStack(spacing: 1) {
                paneViews
            }
        }
    }

    private var paneViews: some View {
        ForEach(harness.panes) { pane in
            ValidationPaneView(pane: pane, theme: harness.theme)
                .frame(minWidth: 260, minHeight: 180)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Validation")
                .font(.headline)
            Label("Ghostty surface", systemImage: "terminal")
                .labelStyle(.titleAndIcon)
            Label("SwiftUI metadata only", systemImage: "gauge.with.dots.needle.50percent")
                .labelStyle(.titleAndIcon)
            Divider()
                .padding(.vertical, 4)
            Text("Theme")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(TerminalTheme.allCases) { option in
                Button {
                    harness.setTheme(option)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(option.accent)
                            .frame(width: 10, height: 10)
                        Text(option.title)
                        Spacer()
                        if option == harness.theme {
                            Image(systemName: "checkmark")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .foregroundStyle(.primary)
            }
            Divider()
                .padding(.vertical, 4)
            Text("Matrix")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("\(harness.panes.count) surface(s)", systemImage: "square.split.2x1")
                .labelStyle(.titleAndIcon)
            Label(harness.splitAxis.title, systemImage: "rectangle.split.2x1")
                .labelStyle(.titleAndIcon)
            Label("\(harness.commandCount) command(s)", systemImage: "checklist")
                .labelStyle(.titleAndIcon)
            Spacer()
            Text("Transcript is not stored in SwiftUI state.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 220)
        .background(harness.theme.sidebarBackground)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                harness.stressAll()
            } label: {
                Label("Stress All", systemImage: "speedometer")
            }
            .help("Send a 100k-line output command to every pane")

            Button {
                harness.addPane()
            } label: {
                Label("Add Pane", systemImage: "plus.square.on.square")
            }
            .disabled(harness.panes.count >= 4)

            Button {
                harness.closeLastPane()
            } label: {
                Label("Close Pane", systemImage: "minus.square")
            }
            .disabled(harness.panes.count <= 1)

            Button {
                harness.toggleSplitAxis()
            } label: {
                Label("Layout", systemImage: "rectangle.split.2x1")
            }

            Button {
                harness.swapPanes()
            } label: {
                Label("Swap", systemImage: "arrow.left.arrow.right")
            }
            .disabled(harness.panes.count <= 1)

            Button {
                harness.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Force all Ghostty surfaces to refresh")

            Spacer()

            Text("\(harness.theme.title) / \(harness.panes.count) GhosttyKit surface(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(harness.theme.sidebarBackground.opacity(0.9))
    }
}

struct ValidationPaneView: View {
    @ObservedObject var pane: ValidationPane
    let theme: TerminalTheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                Text(pane.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    pane.owner.sendStressCommand()
                } label: {
                    Image(systemName: "speedometer")
                }
                .buttonStyle(.borderless)
                .help("Stress this pane")
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(theme.sidebarBackground.opacity(0.9))

            TerminalSurfaceRepresentable(owner: pane.owner, theme: theme)
                .background(theme.shellBackground)
        }
    }
}

struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let owner: TerminalSurfaceOwner
    let theme: TerminalTheme

    func makeNSView(context: Context) -> TerminalHostView {
        owner.applyTheme(theme)
        return owner.hostView
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        owner.applyTheme(theme)
        owner.attachIfPossible()
    }
}
