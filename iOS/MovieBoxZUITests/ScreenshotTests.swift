import XCTest

/// Captures App Store screenshots by driving the real app UI, then attaching a
/// full-resolution, correctly-oriented screenshot of each key screen. Run on
/// each device you need (iPhone 6.9", iPad 12.9"). Attachments are exported
/// from the .xcresult afterwards.
final class ScreenshotTests: MovieBoxZUITestCase {

    func testCaptureAppStoreScreens() {
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 30),
                      "Browse tab should appear after launch")

        // Let the catalog load and the hero carousel advance to a movie with a
        // real landscape backdrop (index 0 is often poster-only).
        sleep(22)
        snapshot("01_Browse")

        // Scroll down to reveal the genre / era rails, then back to the top.
        app.swipeUp()
        app.swipeUp()
        sleep(2)
        snapshot("02_BrowseRails")
        app.swipeDown()
        app.swipeDown()
        sleep(1)

        tapTab("TV Series"); sleep(6); snapshot("03_TVSeries")
        tapTab("Kids");      sleep(6); snapshot("04_Kids")
        tapTab("Search");    sleep(2); snapshot("05_Search")
        tapTab("Library");   sleep(3); snapshot("06_Library")
    }

    // MARK: - Helpers

    private func tapTab(_ name: String) {
        let button = app.buttons[name]
        if button.waitForExistence(timeout: 10) {
            button.tap()
        } else {
            XCTFail("Tab '\(name)' not found")
        }
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
