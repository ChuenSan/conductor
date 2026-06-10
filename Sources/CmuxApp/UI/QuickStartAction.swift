import SwiftUI

struct QuickStartAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let run: () -> Void

    init(id: String, title: String, systemImage: String, isPrimary: Bool = false, run: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.run = run
    }
}
