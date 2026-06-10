import XCTest
@testable import CmuxCore

final class KeyChordTests: XCTestCase {
    func testParseSimple() {
        let chord = KeyChord(parsing: "cmd+t")
        XCTAssertEqual(chord, KeyChord(modifiers: .command, key: "t"))
    }

    func testParseMultipleModifiers() {
        let chord = KeyChord(parsing: "cmd+shift+d")
        XCTAssertEqual(chord?.modifiers, [.command, .shift])
        XCTAssertEqual(chord?.key, "d")
    }

    func testParseAliases() {
        XCTAssertEqual(KeyChord(parsing: "command+t"), KeyChord(parsing: "cmd+t"))
        XCTAssertEqual(KeyChord(parsing: "⌘+t")?.modifiers, .command)
        XCTAssertEqual(KeyChord(parsing: "opt+left")?.modifiers, .option)
        XCTAssertEqual(KeyChord(parsing: "control+a")?.modifiers, .control)
    }

    func testParseArrowAndSpecialKeys() {
        XCTAssertEqual(KeyChord(parsing: "cmd+alt+right")?.key, "right")
        XCTAssertEqual(KeyChord(parsing: "cmd+return")?.key, "enter")
        XCTAssertEqual(KeyChord(parsing: "escape")?.key, "esc")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(KeyChord(parsing: "CMD+T"), KeyChord(modifiers: .command, key: "t"))
    }

    func testMinusAndEqualsAreValidKeys() {
        // 字号缩放用：cmd+- / cmd+= / cmd+0
        XCTAssertEqual(KeyChord(parsing: "cmd+-"), KeyChord(modifiers: .command, key: "-"))
        XCTAssertEqual(KeyChord(parsing: "cmd+="), KeyChord(modifiers: .command, key: "="))
        XCTAssertEqual(KeyChord(parsing: "cmd+0"), KeyChord(modifiers: .command, key: "0"))
    }

    func testInvalidStrings() {
        XCTAssertNil(KeyChord(parsing: "cmd"))          // 只有修饰键、无主键
        XCTAssertNil(KeyChord(parsing: ""))             // 空
        XCTAssertNil(KeyChord(parsing: "cmd+a+b"))      // 两个主键
    }

    func testHashableEquality() {
        let a = KeyChord(modifiers: [.command, .shift], key: "d")
        let b = KeyChord(parsing: "shift+cmd+d")        // 顺序无关
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b?.hashValue)
    }
}
