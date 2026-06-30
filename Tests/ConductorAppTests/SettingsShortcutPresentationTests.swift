@testable import ConductorApp
import XCTest

final class SettingsShortcutPresentationTests: XCTestCase {
    private func commands() -> [AppCommand] {
        [
            AppCommand(id: "openSettings", title: "打开设置", defaultKeybinding: "cmd+,", scope: .global) {},
            AppCommand(id: "newTab", title: "新建标签", defaultKeybinding: "cmd+t", scope: .workspace) {},
            AppCommand(id: "splitRight", title: "向右分屏", defaultKeybinding: "cmd+d", scope: .pane) {},
            AppCommand(id: "copyPane", title: "复制（当前面板）", defaultKeybinding: nil, scope: .pane) {},
        ]
    }

    func testShortcutRowsAreGroupedByCommandScope() {
        let rows = ShortcutSettingsModel.rows(commands: commands(), overrides: [:])
        let groups = ShortcutSettingsModel.groupedRows(rows)

        XCTAssertEqual(groups.map(\.title), ["全局", "工作区", "面板"])
        XCTAssertEqual(groups[2].rows.map(\.id), ["splitRight", "copyPane"])
    }

    func testShortcutSectionShowsFilterCounts() {
        let rows = ShortcutSettingsModel.rows(
            commands: commands(),
            overrides: [
                "newTab": "cmd+d",
                "copyPane": ""
            ]
        )

        let counts = ShortcutSettingsModel.filterCounts(for: rows)

        XCTAssertEqual(counts[.all], 4)
        XCTAssertEqual(counts[.modified], 2)
        XCTAssertEqual(counts[.unassigned], 1)
        XCTAssertEqual(counts[.conflicts], 2)
    }
}
