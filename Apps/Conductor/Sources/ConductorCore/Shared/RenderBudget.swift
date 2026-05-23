import Foundation

public enum RenderBudget {
    public static let smallListLimit = 100
    public static let mediumListLimit = 250
    public static let largeListPreviewLimit = 1_000
    public static let defaultVisibleRows = 40
    public static let defaultOverscanRows = 12

    public static func visibleRowWindow(
        defaultVisibleCount: Int = defaultVisibleRows,
        overscan: Int = defaultOverscanRows
    ) -> Int {
        max(1, defaultVisibleCount + overscan * 2)
    }
}
