import ConductorCore
import SwiftUI

struct SplitNodeView: View {
    let node: SplitNode
    @ObservedObject var model: ConductorWindowModel
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    var path: [SplitPathElement] = []

    var body: some View {
        switch node {
        case let .leaf(paneID):
            if let pane = model.workspace.panes[paneID] {
                TerminalPaneView(
                    pane: pane,
                    model: model,
                    snapshot: TerminalPaneChromeSnapshot(
                        pane: pane,
                        model: model,
                        theme: theme,
                        appearance: appearance
                    )
                )
                    .frame(minWidth: 0, minHeight: 0)
                    .clipped()
                    .transition(.identity)
            }
        case let .split(axis, first, second, fraction):
            SplitPairView(
                axis: axis,
                fraction: fraction,
                first: first,
                second: second,
                path: path,
                model: model,
                theme: theme,
                appearance: appearance
            )
            .transition(.identity)
        }
    }
}
private struct SplitPairView: View {
    let axis: SplitAxis
    let fraction: Double
    let first: SplitNode
    let second: SplitNode
    let path: [SplitPathElement]
    let model: ConductorWindowModel
    let theme: TerminalTheme
    let appearance: AppearancePreferences

    var body: some View {
        AppKitSplitPairView(
            axis: axis,
            fraction: fraction,
            first: first,
            second: second,
            path: path,
            model: model,
            theme: theme,
            appearance: appearance,
            dividerThickness: ConductorTokens.Space.splitGutter
        )
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }
}
