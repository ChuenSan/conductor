import Testing
@testable import ConductorCore

@Test func renderBudgetDefaults() {
    #expect(RenderBudget.smallListLimit == 100, "small render budget should be capped")
    #expect(RenderBudget.mediumListLimit == 250, "medium render budget should be capped")
    #expect(RenderBudget.largeListPreviewLimit == 1_000, "large preview budget should be bounded")
    #expect(RenderBudget.defaultVisibleRows == 40, "default visible row budget should match expected viewport")
    #expect(RenderBudget.defaultOverscanRows == 12, "default overscan budget should be bounded")
    #expect(RenderBudget.visibleRowWindow(defaultVisibleCount: 40, overscan: 12) == 64, "visible row window should include overscan")
}
