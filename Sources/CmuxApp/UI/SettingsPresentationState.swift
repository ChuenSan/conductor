struct SettingsPresentationState: Equatable {
    private(set) var isPresented = false

    mutating func open() {
        isPresented = true
    }

    mutating func close() {
        isPresented = false
    }
}
