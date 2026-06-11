import AppKit

@MainActor
enum WindowChromePolicy {
    static func applyMainWindowChrome(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(AppStyle.windowBackground)
    }
}
