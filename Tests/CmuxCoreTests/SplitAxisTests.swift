import XCTest
@testable import CmuxCore

final class SplitAxisTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(SplitAxis.horizontal.rawValue, "horizontal")
        XCTAssertEqual(SplitAxis.vertical.rawValue, "vertical")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(SplitAxis.vertical)
        let decoded = try JSONDecoder().decode(SplitAxis.self, from: data)
        XCTAssertEqual(decoded, .vertical)
    }
}
