import XCTest
@testable import ConductorCore

final class IdentifiersTests: XCTestCase {
    func testEquality() {
        XCTAssertEqual(PaneID("a"), PaneID("a"))
        XCTAssertNotEqual(PaneID("a"), PaneID("b"))
    }

    func testUsableAsDictKey() {
        var map: [PaneID: Int] = [:]
        map[PaneID("a")] = 1
        XCTAssertEqual(map[PaneID("a")], 1)
    }

    func testCodableRoundTrip() throws {
        let id = WorkspaceID("ws-1")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(WorkspaceID.self, from: data)
        XCTAssertEqual(decoded, id)
    }
}
