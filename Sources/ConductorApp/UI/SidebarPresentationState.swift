struct SidebarPresentationState: Equatable {
    private(set) var isCollapsed = false

    mutating func toggle() {
        isCollapsed.toggle()
    }

    mutating func expand() {
        isCollapsed = false
    }
}
