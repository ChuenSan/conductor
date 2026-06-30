@testable import ConductorApp
import Foundation
import XCTest

final class BuiltinAgentPipeWriterTests: XCTestCase {
    func testWriteToClosedPipeReturnsFalseInsteadOfTerminatingProcess() {
        let pipe = Pipe()
        pipe.fileHandleForReading.closeFile()
        defer { try? pipe.fileHandleForWriting.close() }

        let wrote = BuiltinAgentPipeWriter.writeIgnoringSIGPIPE(
            Data("{\"id\":\"r1\"}\n".utf8),
            to: pipe.fileHandleForWriting)

        XCTAssertFalse(wrote)
    }
}
