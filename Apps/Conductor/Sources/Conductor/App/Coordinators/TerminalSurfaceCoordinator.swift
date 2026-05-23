import ConductorCore
import CoreGraphics
import Foundation

@MainActor
struct TerminalSurfaceHandlers {
    let install: (TerminalSurface) -> Void
}

@MainActor
final class TerminalSurfaceCoordinator {
    private var surfaces: [TerminalID: TerminalSurface] = [:]
    private var pendingNavigationRefreshTerminalIDs = Set<TerminalID>()

    var runtimeSurfaceCount: Int {
        surfaces.count
    }

    func hasSurface(for terminalID: TerminalID) -> Bool {
        surfaces[terminalID] != nil
    }

    func surface(
        for tab: TerminalTabState,
        theme: TerminalTheme,
        terminalFontSize: CGFloat,
        handlers: TerminalSurfaceHandlers
    ) -> TerminalSurface {
        if let surface = surfaces[tab.id] {
            return surface
        }
        let surface = TerminalSurface(
            id: tab.id,
            theme: theme,
            terminalFontSize: terminalFontSize,
            workingDirectory: tab.workingDirectory
        )
        handlers.install(surface)
        surfaces[tab.id] = surface
        return surface
    }

    func existingSurface(for terminalID: TerminalID) -> TerminalSurface? {
        surfaces[terminalID]
    }

    func closeSurfaces(for terminalIDs: [TerminalID]) {
        for terminalID in terminalIDs {
            surfaces.removeValue(forKey: terminalID)?.close()
            pendingNavigationRefreshTerminalIDs.remove(terminalID)
        }
    }

    func closeAllSurfaces() {
        surfaces.values.forEach { $0.close() }
        surfaces.removeAll()
        pendingNavigationRefreshTerminalIDs.removeAll()
    }

    func applyAppearance(theme: TerminalTheme, terminalFontSize: CGFloat) {
        surfaces.values.forEach {
            $0.applyAppearance(theme: theme, terminalFontSize: terminalFontSize)
        }
    }

    func setFocusedTerminal(_ focusedTerminalID: TerminalID?) {
        for (terminalID, surface) in surfaces {
            surface.setFocused(terminalID == focusedTerminalID)
        }
    }

    func markPendingNavigationRefresh(_ terminalID: TerminalID) -> Bool {
        pendingNavigationRefreshTerminalIDs.insert(terminalID).inserted
    }

    func clearPendingNavigationRefresh(_ terminalID: TerminalID) {
        pendingNavigationRefreshTerminalIDs.remove(terminalID)
    }
}
