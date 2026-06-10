import XCTest
@testable import CmuxCore

final class CwdResolverTests: XCTestCase {
    func testUsesCwdWhenItExists() {
        let result = CwdResolver.resolve(
            cwd: "/proj/sub", workspacePath: "/proj", home: "/Users/me",
            exists: { $0 == "/proj/sub" }
        )
        XCTAssertEqual(result, "/proj/sub")
    }

    func testFallsBackToWorkspaceWhenCwdMissing() {
        let result = CwdResolver.resolve(
            cwd: "/proj/sub", workspacePath: "/proj", home: "/Users/me",
            exists: { $0 == "/proj" }
        )
        XCTAssertEqual(result, "/proj")
    }

    func testFallsBackToHomeWhenBothMissing() {
        let result = CwdResolver.resolve(
            cwd: "/proj/sub", workspacePath: "/proj", home: "/Users/me",
            exists: { _ in false }
        )
        XCTAssertEqual(result, "/Users/me")
    }
}
