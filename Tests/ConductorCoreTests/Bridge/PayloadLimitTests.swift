@testable import ConductorCore
import XCTest

final class PayloadLimitTests: XCTestCase {
    func testContentLengthValidation() {
        XCTAssertEqual(PayloadLimit.validateContentLength(nil), .success(0))
        XCTAssertEqual(PayloadLimit.validateContentLength("abc"), .failure(.invalidContentLength("abc")))
        XCTAssertEqual(PayloadLimit.validateContentLength("-1"), .failure(.invalidContentLength("-1")))
        XCTAssertEqual(PayloadLimit.validateContentLength("4194304"), .success(4_194_304))
        XCTAssertEqual(PayloadLimit.validateContentLength("4194305"), .failure(.tooLarge(4_194_305, 4_194_304)))

        switch PayloadLimit.validateContentLength(String(repeating: "9", count: 100)) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.invalidContentLength):
            XCTFail("Expected payload too large")
        case .failure(.tooLarge(_, let maxBytes)):
            XCTAssertEqual(maxBytes, 4_194_304)
        }
    }

    func testFrameLengthValidation() {
        switch PayloadLimit.validateFrameLength(4_194_304) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }

        switch PayloadLimit.validateFrameLength(4_194_305) {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error, .tooLarge(4_194_305, 4_194_304))
        }
    }
}
