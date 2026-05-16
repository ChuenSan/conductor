import Foundation
import SwiftUI

@MainActor
final class ValidationHarness: ObservableObject {
    enum SplitAxis: String {
        case horizontal
        case vertical

        var title: String {
            switch self {
            case .horizontal: "Columns"
            case .vertical: "Rows"
            }
        }
    }

    @Published var panes: [ValidationPane]
    @Published var theme: TerminalTheme = .flexoki
    @Published var splitAxis: SplitAxis = .horizontal
    @Published private(set) var commandCount = 0

    init() {
        panes = [ValidationPane(index: 1)]
    }

    func addPane() {
        guard panes.count < 4 else { return }
        panes.append(ValidationPane(index: panes.count + 1))
        commandCount += 1
        ValidationLogger.info("validation add pane count=\(panes.count)")
    }

    func closeLastPane() {
        guard panes.count > 1, let pane = panes.popLast() else { return }
        pane.owner.close()
        commandCount += 1
        ValidationLogger.info("validation close pane count=\(panes.count)")
    }

    func toggleSplitAxis() {
        splitAxis = splitAxis == .horizontal ? .vertical : .horizontal
        commandCount += 1
        ValidationLogger.info("validation split axis=\(splitAxis.title)")
    }

    func swapPanes() {
        guard panes.count > 1 else { return }
        panes.swapAt(0, panes.count - 1)
        commandCount += 1
        ValidationLogger.info("validation swap panes count=\(panes.count)")
    }

    func stressAll() {
        commandCount += 1
        for pane in panes {
            pane.owner.sendStressCommand()
        }
        ValidationLogger.info("validation stress all count=\(panes.count)")
    }

    func refreshAll() {
        commandCount += 1
        for pane in panes {
            pane.owner.refresh()
        }
    }

    func setTheme(_ theme: TerminalTheme) {
        self.theme = theme
        commandCount += 1
        for pane in panes {
            pane.owner.applyTheme(theme)
        }
        ValidationLogger.info("validation theme=\(theme.title)")
    }

    func closeAll() {
        for pane in panes {
            pane.owner.close()
        }
    }

    func runAutomatedValidation() {
        ValidationLogger.info("automated validation begin")
        while panes.count < 3 {
            addPane()
        }
        toggleSplitAxis()
        swapPanes()
        setTheme(.poimandres)
        refreshAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            for (offset, pane) in self.panes.enumerated() {
                pane.owner.sendTypedText("printf pane-\(offset + 1)-ok > /tmp/ghostty-pane-\(offset + 1)-validation.txt\r")
            }

            guard let first = self.panes.first else { return }
            first.owner.sendAutomationText("printf '中文-paste-ok' > /tmp/ghostty-paste-validation.txt\n")
            first.owner.sendTypedText("cat > /tmp/ghostty-ctrl-validation.txt\rctrl-body-ok\r")
            first.owner.sendControlDForValidation()
            first.owner.hostView.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            first.owner.hostView.unmarkText()
            first.owner.hostView.insertText("printf '中文-ime-ok' > /tmp/ghostty-ime-validation.txt\r", replacementRange: NSRange(location: NSNotFound, length: 0))
            self.stressAll()
            ValidationLogger.info("automated validation commands sent")
        }
    }
}

@MainActor
final class ValidationPane: Identifiable, ObservableObject {
    let id = UUID()
    let owner = TerminalSurfaceOwner()
    let index: Int

    init(index: Int) {
        self.index = index
    }

    var title: String {
        "Pane \(index)"
    }
}
