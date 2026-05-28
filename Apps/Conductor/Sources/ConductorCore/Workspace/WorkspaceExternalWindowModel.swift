import Foundation

public struct ExternalWindowTabID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct WorkspaceExternalWindowTabState: Identifiable, Codable, Equatable, Sendable {
    public var id: ExternalWindowTabID
    public var windowNumber: Int
    public var ownerProcessIdentifier: Int32
    public var bundleIdentifier: String?
    public var ownerName: String
    public var windowTitle: String
    public var attached: Bool

    public init(
        id: ExternalWindowTabID = ExternalWindowTabID(),
        windowNumber: Int,
        ownerProcessIdentifier: Int32,
        bundleIdentifier: String? = nil,
        ownerName: String,
        windowTitle: String,
        attached: Bool = true
    ) {
        self.id = id
        self.windowNumber = windowNumber
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.attached = attached
    }

    public var displayTitle: String {
        let cleanTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            return cleanTitle
        }
        return ownerName
    }
}
