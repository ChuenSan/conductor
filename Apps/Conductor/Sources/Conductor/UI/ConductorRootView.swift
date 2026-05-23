import SwiftUI

struct ConductorRootView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        ShellRootView(model: model)
    }
}
