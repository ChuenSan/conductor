@testable import ConductorApp
import XCTest

final class ShortcutSettingsModelTests: XCTestCase {
    private func commands() -> [AppCommand] {
        [
            AppCommand(id: "newTab", title: "新建标签", defaultKeybinding: "cmd+t", scope: .workspace) {},
            AppCommand(id: "splitRight", title: "向右分屏", defaultKeybinding: "cmd+d", scope: .pane) {},
            AppCommand(id: "splitDown", title: "向下分屏", defaultKeybinding: "cmd+shift+d", scope: .pane) {},
            AppCommand(id: "copyPane", title: "复制（当前面板）", defaultKeybinding: nil, scope: .pane) {},
        ]
    }

    func testRowsExposeModifiedDisabledAndConflictState() {
        let rows = ShortcutSettingsModel.rows(
            commands: commands(),
            overrides: [
                "splitRight": "cmd+t",
                "copyPane": ""
            ]
        )

        let splitRight = try! XCTUnwrap(rows.first { $0.id == "splitRight" })
        XCTAssertTrue(splitRight.isModified)
        XCTAssertFalse(splitRight.isDisabled)
        XCTAssertEqual(splitRight.effectiveKeybinding, "cmd+t")
        XCTAssertEqual(splitRight.conflictingCommandTitles, ["新建标签"])

        let copyPane = try! XCTUnwrap(rows.first { $0.id == "copyPane" })
        XCTAssertTrue(copyPane.isModified)
        XCTAssertTrue(copyPane.isDisabled)
        XCTAssertNil(copyPane.effectiveKeybinding)
        XCTAssertTrue(copyPane.conflictingCommandTitles.isEmpty)
    }

    func testFilterCountsIncludeModifiedUnassignedAndConflicts() {
        let rows = ShortcutSettingsModel.rows(
            commands: commands(),
            overrides: [
                "splitRight": "cmd+t",
                "copyPane": ""
            ]
        )

        XCTAssertEqual(ShortcutSettingsModel.count(rows, matching: .all), 4)
        XCTAssertEqual(ShortcutSettingsModel.count(rows, matching: .modified), 2)
        XCTAssertEqual(ShortcutSettingsModel.count(rows, matching: .unassigned), 1)
        XCTAssertEqual(ShortcutSettingsModel.count(rows, matching: .conflicts), 2)
    }

    func testSearchMatchesCommandTitleIDLayerAndShortcut() {
        let rows = ShortcutSettingsModel.rows(commands: commands(), overrides: [:])

        XCTAssertEqual(
            ShortcutSettingsModel.filteredRows(rows, query: "splitright", filter: .all).map(\.id),
            ["splitRight"]
        )
        XCTAssertEqual(
            ShortcutSettingsModel.filteredRows(rows, query: "面板", filter: .all).map(\.id),
            ["splitRight", "splitDown", "copyPane"]
        )
        XCTAssertEqual(
            ShortcutSettingsModel.filteredRows(rows, query: "⌘⇧D", filter: .all).map(\.id),
            ["splitDown"]
        )
    }

    func testCaptureRejectsConflictingShortcut() {
        let result = ShortcutSettingsModel.configByAssigningShortcut(
            commandID: "splitRight",
            shortcut: "cmd+t",
            commands: commands(),
            currentKeybindings: [:]
        )

        switch result {
        case .success:
            XCTFail("Expected conflict")
        case let .failure(error):
            XCTAssertTrue(error.message.contains("新建标签"))
            XCTAssertTrue(error.message.contains("⌘T"))
        }
    }

    func testAssigningDefaultRemovesOverrideAndDisableWritesEmptyOverride() throws {
        let reset = try ShortcutSettingsModel.configByAssigningShortcut(
            commandID: "splitRight",
            shortcut: "cmd+d",
            commands: commands(),
            currentKeybindings: ["splitRight": "cmd+shift+x"]
        ).get()
        XCTAssertNil(reset["splitRight"])

        let disabled = ShortcutSettingsModel.configByDisablingShortcut(
            commandID: "splitRight",
            currentKeybindings: reset
        )
        XCTAssertEqual(disabled["splitRight"], "")
    }
}
