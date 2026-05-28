import AppKit
import ConductorCore
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ExternalWindowCandidate: Identifiable, Equatable {
    var id: Int { windowNumber }
    let windowNumber: Int
    let ownerProcessIdentifier: Int32
    let bundleIdentifier: String?
    let ownerName: String
    let windowTitle: String
    let bounds: CGRect

    var displayTitle: String {
        let cleanTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? ownerName : cleanTitle
    }

    var subtitle: String {
        ownerName
    }

    var appIcon: NSImage {
        if let app = NSRunningApplication(processIdentifier: ownerProcessIdentifier),
           let icon = app.icon {
            return icon
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    var tabState: WorkspaceExternalWindowTabState {
        WorkspaceExternalWindowTabState(
            windowNumber: windowNumber,
            ownerProcessIdentifier: ownerProcessIdentifier,
            bundleIdentifier: bundleIdentifier,
            ownerName: ownerName,
            windowTitle: windowTitle
        )
    }
}

enum ExternalWindowPortalService {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestAccessibilityTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestScreenCaptureTrust() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func availableWindows() -> [ExternalWindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let boundsValue = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                return nil
            }

            let bounds = CGRect(
                x: boundsValue["X"] ?? 0,
                y: boundsValue["Y"] ?? 0,
                width: boundsValue["Width"] ?? 0,
                height: boundsValue["Height"] ?? 0
            )
            guard bounds.width >= 160, bounds.height >= 120 else { return nil }

            let title = (info[kCGWindowName as String] as? String) ?? ""
            let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
            return ExternalWindowCandidate(
                windowNumber: number,
                ownerProcessIdentifier: ownerPID,
                bundleIdentifier: bundleIdentifier,
                ownerName: ownerName,
                windowTitle: title,
                bounds: bounds
            )
        }
    }

    static func isWindowAvailable(_ tab: WorkspaceExternalWindowTabState) -> Bool {
        candidate(for: tab) != nil
    }

    static func candidate(for tab: WorkspaceExternalWindowTabState) -> ExternalWindowCandidate? {
        availableWindows().first { $0.windowNumber == tab.windowNumber && $0.ownerProcessIdentifier == tab.ownerProcessIdentifier }
    }

    static func snapshot(for tab: WorkspaceExternalWindowTabState) async -> NSImage? {
        guard isScreenCaptureTrusted else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == CGWindowID(tab.windowNumber) }) else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.captureResolution = .best

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height))
        } catch {
            return nil
        }
    }

    static func focus(_ tab: WorkspaceExternalWindowTabState) {
        NSRunningApplication(processIdentifier: tab.ownerProcessIdentifier)?.activate(options: [])
        guard let window = accessibilityWindow(for: tab) else { return }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    @discardableResult
    static func fit(_ tab: WorkspaceExternalWindowTabState, to appKitRect: CGRect) -> Bool {
        guard isAccessibilityTrusted,
              let window = accessibilityWindow(for: tab) else {
            return false
        }

        let target = rectForAccessibility(fromAppKitScreenRect: appKitRect)
            .insetBy(dx: 10, dy: 10)
        var origin = target.origin
        var size = target.size
        guard let originValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        NSRunningApplication(processIdentifier: tab.ownerProcessIdentifier)?.activate(options: [])
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return positionResult == .success || sizeResult == .success
    }

    private static func accessibilityWindow(for tab: WorkspaceExternalWindowTabState) -> AXUIElement? {
        let app = AXUIElementCreateApplication(tab.ownerProcessIdentifier)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement] else {
            return nil
        }

        if let matched = windows.first(where: { windowNumber(of: $0) == tab.windowNumber }) {
            return matched
        }

        let cleanTitle = tab.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty,
           let matched = windows.first(where: { title(of: $0) == cleanTitle }) {
            return matched
        }
        return windows.first
    }

    private static func windowNumber(of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func rectForAccessibility(fromAppKitScreenRect rect: CGRect) -> CGRect {
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? rect.maxY
        return CGRect(
            x: rect.minX,
            y: maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
