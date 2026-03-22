import XCTest

/// Tests the core navigation structure — tab switching, splash → browse.
/// iOS 18 SwiftUI TabView does not expose as UITabBar — tab items queried as app.buttons.
final class AppNavigationTests: MovieBoxZUITestCase {

    // MARK: - Splash screen

    func testAppLaunchesAndShowsTabBar() {
        // Verify the app successfully launches past the splash into the main UI.
        // app.buttons["Browse"] is the most reliable indicator — always present after splash.
        XCTAssert(app.buttons["Browse"].waitForExistence(timeout: 10),
                  "App should launch and show Browse tab after splash")
    }

    // MARK: - Tab buttons

    func testBrowseTabButtonExists() {
        XCTAssert(app.buttons["Browse"].waitForExistence(timeout: 10),
                  "Browse tab button should appear after splash")
    }

    func testAllTabButtonsExist() {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        for tab in ["Browse", "Search", "Library", "Settings"] {
            XCTAssert(app.buttons[tab].exists, "Tab '\(tab)' should exist")
        }
    }

    // MARK: - Tab navigation

    func testTapSearchTab() {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        app.buttons["Search"].tap()
        // SearchView uses SwiftUI TextField (not UISearchBar) — must query textFields
        XCTAssert(app.textFields.firstMatch.waitForExistence(timeout: 5),
                  "Search field should appear after tapping Search tab")
    }

    func testTapLibraryTab() {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        app.buttons["Library"].tap()
        // "My Library" header is always present even when the list is empty
        XCTAssert(app.staticTexts["My Library"].waitForExistence(timeout: 5),
                  "Library header should appear")
    }

    func testTapSettingsTab() {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        app.buttons["Settings"].tap()
        XCTAssert(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                  "Settings nav bar should appear")
    }

    func testNavigateAcrossAllTabs() {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        for tab in ["Search", "Library", "Settings", "Browse"] {
            app.buttons[tab].tap()
            XCTAssert(app.buttons[tab].exists, "'\(tab)' button should still exist after tap")
        }
    }

    func testReturnToBrowseFromSettings() {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        app.buttons["Settings"].tap()
        app.buttons["Browse"].tap()
        XCTAssert(app.scrollViews.firstMatch.waitForExistence(timeout: 8),
                  "Browse content should reappear after returning")
    }
}
