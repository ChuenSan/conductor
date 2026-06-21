@testable import ConductorApp
import XCTest

final class CommandDeckScopeTests: XCTestCase {
    func testMajorCommandIDsResolveToCommandDeckLayers() {
        let expectations: [String: CommandDeckLayer] = [
            "openSettings": .global,
            "commandPalette": .global,
            "shortcutCheatSheet": .global,
            "newTab": .workspace,
            "nextTab": .workspace,
            "prevTab": .workspace,
            "splitRight": .pane,
            "splitDown": .pane,
            "closePane": .pane,
            "toggleZoom": .pane,
            "findInTerminal": .pane,
            "taskCards": .task,
            "openSnippets": .capability,
            "coCreate": .capability,
            "queuePrompt": .agent,
            "missionControl": .agent,
        ]

        for (commandID, layer) in expectations {
            XCTAssertEqual(CommandDeckCommandScope.scope(forCommandID: commandID), layer, commandID)
        }
    }

    func testSelectTabCommandsAreWorkspaceScoped() {
        for index in 1...9 {
            XCTAssertEqual(CommandDeckCommandScope.scope(forCommandID: "selectTab\(index)"), .workspace)
        }
    }

    func testAppCommandDefaultsScopeFromID() {
        let command = AppCommand(id: "splitRight", title: "Split", defaultKeybinding: nil) {}

        XCTAssertEqual(command.scope, .pane)
    }

    func testCommandDeckLayerHasStableLocalizedTitles() {
        XCTAssertEqual(CommandDeckLayer.global.title, "全局")
        XCTAssertEqual(CommandDeckLayer.workspace.title, "工作区")
        XCTAssertEqual(CommandDeckLayer.pane.title, "面板")
        XCTAssertEqual(CommandDeckLayer.agent.title, "Agent")
        XCTAssertEqual(CommandDeckLayer.capability.title, "能力")
        XCTAssertEqual(CommandDeckLayer.task.title, "任务")
    }
}
