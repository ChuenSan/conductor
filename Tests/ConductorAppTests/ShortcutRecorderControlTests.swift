@testable import ConductorApp
import AppKit
import XCTest

final class ShortcutRecorderControlTests: XCTestCase {
    func testCaptureDisplayUsesSymbolizedShortcut() {
        XCTAssertEqual(ShortcutRecorderPresentation.displayText(for: "cmd+shift+d", isRecording: false), "⇧⌘D")
        XCTAssertEqual(ShortcutRecorderPresentation.displayText(for: nil, isRecording: false), "录入")
    }

    func testRecordingPromptAndAccessibilityLabel() {
        XCTAssertEqual(ShortcutRecorderPresentation.displayText(for: "cmd+d", isRecording: true), "按下快捷键…")
        XCTAssertEqual(
            ShortcutRecorderPresentation.accessibilityLabel(
                commandTitle: "向右分屏",
                shortcut: "cmd+d",
                isRecording: false
            ),
            "修改 向右分屏 快捷键，当前为 ⌘D"
        )
        XCTAssertEqual(
            ShortcutRecorderPresentation.accessibilityLabel(
                commandTitle: "复制",
                shortcut: nil,
                isRecording: false
            ),
            "设置 复制 快捷键"
        )
    }

    func testEventCaptureNormalizesCommandShiftD() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "D",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))

        XCTAssertEqual(ShortcutRecorderPresentation.captureSpec(from: event), "cmd+shift+d")
    }

    func testEventCaptureIgnoresModifierOnlyKeys() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 55
        ))

        XCTAssertNil(ShortcutRecorderPresentation.captureSpec(from: event))
    }

    func testFocusStateTracksRecordingMode() {
        ShortcutRecorderFocusState.shared.isRecording = false
        XCTAssertFalse(ShortcutRecorderFocusState.shared.isRecording)

        ShortcutRecorderFocusState.shared.isRecording = true
        XCTAssertTrue(ShortcutRecorderFocusState.shared.isRecording)

        ShortcutRecorderFocusState.shared.isRecording = false
        XCTAssertFalse(ShortcutRecorderFocusState.shared.isRecording)
    }
}
