import Foundation

public enum CodexBarDisplayBrand {
    public static var productName: String {
        self.isRunningInsideConductor ? "Conductor Usage" : "CodexBar"
    }

    public static var hostAppName: String {
        self.isRunningInsideConductor ? "Conductor" : "CodexBar"
    }

    public static var statusItemAccessibilityIdentifierPrefix: String {
        self.isRunningInsideConductor ? "ConductorUsage.StatusItem" : "CodexBar.StatusItem"
    }

    public static var isRunningInsideConductor: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["CONDUCTOR_USAGE_BRANDING"] == "1" {
            return true
        }
        if environment["CONDUCTOR_DISABLE_USAGE_BRANDING"] == "1" {
            return false
        }

        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName == "conductor" {
            return true
        }

        let bundleID = Bundle.main.bundleIdentifier?.lowercased() ?? ""
        return bundleID.hasPrefix("app.conductor")
    }

    public static func userFacing(_ text: String) -> String {
        guard self.isRunningInsideConductor else { return text }
        return text
            .replacingOccurrences(of: "CodexBarCLI", with: "Conductor Usage CLI")
            .replacingOccurrences(of: "CodexBar", with: self.productName)
            .replacingOccurrences(of: "~/.codexbar/config.json", with: "the local Conductor Usage config")
    }
}
