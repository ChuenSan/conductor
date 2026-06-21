@testable import ConductorApp
import XCTest

final class SidebarWorkspaceDragPolicyTests: XCTestCase {
    func testWorkspaceReorderDragRemainsAvailableFromWorkspaceRows() {
        XCTAssertTrue(WorkspaceReorderDragPolicy.rowStartsDrag)
        XCTAssertTrue(WorkspaceReorderDragPolicy.handleStartsDrag)
        XCTAssertGreaterThanOrEqual(WorkspaceReorderDragPolicy.handleWidth, 18)
    }
}
