import ConductorCore
import SwiftUI

struct ConductorWebSurfaceView: View {
    let tab: WorkspaceWebTabState
    let navigationGeneration: Int
    let reloadGeneration: Int
    let stopGeneration: Int
    let backGeneration: Int
    let forwardGeneration: Int
    let findQuery: String
    let findGeneration: Int
    let findBackwards: Bool
    let model: ConductorWindowModel

    var body: some View {
        ConductorWebKitSurfaceRepresentable(
            tab: tab,
            navigationGeneration: navigationGeneration,
            reloadGeneration: reloadGeneration,
            stopGeneration: stopGeneration,
            backGeneration: backGeneration,
            forwardGeneration: forwardGeneration,
            findQuery: findQuery,
            findGeneration: findGeneration,
            findBackwards: findBackwards,
            model: model
        )
    }
}
