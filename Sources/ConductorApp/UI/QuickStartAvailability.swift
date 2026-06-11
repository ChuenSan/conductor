enum QuickStartAvailability {
    static func showsEmptyIllustration(tabCount: Int?, totalPaneCount: Int?, isPanelPresented: Bool) -> Bool {
        tabCount == 0 && totalPaneCount == 0 && !isPanelPresented
    }
}
