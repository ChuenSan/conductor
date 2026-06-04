import Foundation

enum ConductorShellToastTone: String, Equatable, Sendable {
    case info
    case warning
    case error
}

enum ConductorShellToastAction: String, Equatable, Sendable {
    case openNotificationSettings
    case checkNotificationPermission
}

struct ConductorShellToast: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let systemImage: String
    let tone: ConductorShellToastTone
    let actionTitle: String?
    let action: ConductorShellToastAction?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        systemImage: String,
        tone: ConductorShellToastTone = .info,
        actionTitle: String? = nil,
        action: ConductorShellToastAction? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.systemImage = systemImage
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }
}
