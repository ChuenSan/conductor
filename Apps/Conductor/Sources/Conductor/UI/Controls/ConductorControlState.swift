import Foundation

struct ConductorControlState: Equatable, Identifiable, Sendable {
    let id: String
    let title: String?
    let systemImage: String
    let isEnabled: Bool
    let isActive: Bool
    let tooltip: String
    let accessibilityLabel: String

    init(
        id: String,
        title: String? = nil,
        systemImage: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        tooltip: String,
        accessibilityLabel: String
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
    }
}
