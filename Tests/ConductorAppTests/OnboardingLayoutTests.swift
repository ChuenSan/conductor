@testable import ConductorApp
import XCTest

final class OnboardingLayoutTests: XCTestCase {
    func testScreenshotIsPrimaryVisualInIntroDialog() {
        XCTAssertGreaterThanOrEqual(OnboardingLayout.screenshotSize.width, 520)
        XCTAssertGreaterThan(OnboardingLayout.screenshotSize.width / OnboardingLayout.dialogSize.width, 0.55)
        XCTAssertEqual(
            OnboardingLayout.screenshotSize.height / OnboardingLayout.screenshotSize.width,
            0.75,
            accuracy: 0.001
        )
    }

    func testScreenshotPreviewHasAFramedInnerImage() {
        XCTAssertGreaterThan(OnboardingLayout.screenshotMatPadding, 10)
        XCTAssertLessThan(OnboardingLayout.screenshotInnerSize.width, OnboardingLayout.screenshotSize.width)
        XCTAssertLessThan(OnboardingLayout.screenshotInnerSize.height, OnboardingLayout.screenshotSize.height)
    }

    func testToolAndSettingsPagesFocusTheRightSidePanel() {
        let focusedPages = OnboardingCatalog.pages.filter {
            $0.screenshotName == "onboarding-tools" || $0.screenshotName == "onboarding-settings"
        }

        XCTAssertFalse(focusedPages.isEmpty)
        XCTAssertTrue(focusedPages.allSatisfy { $0.screenshotFocus.scale >= 1.14 })
        XCTAssertTrue(focusedPages.allSatisfy { $0.screenshotFocus.offset.width < 0 })
    }
}
