import XCTest

/// Page object for the Browse (home) tab.
struct BrowsePage {
    let app: XCUIApplication

    // iOS 18 SwiftUI TabView does not expose as UITabBar — query buttons directly.
    var tabItem: XCUIElement { app.buttons["Browse"] }
    var searchTabButton: XCUIElement { app.buttons["Search"] }
    var libraryTabButton: XCUIElement { app.buttons["Library"] }
    var settingsTabButton: XCUIElement { app.buttons["Settings"] }

    // The scroll view containing all the carousels
    var contentScroll: XCUIElement { app.scrollViews.firstMatch }

    // Loading skeleton — visible during initial fetch
    var loadingIndicator: XCUIElement { app.activityIndicators.firstMatch }

    /// Waits for content to appear (skeleton to go away and scroll to exist).
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 15) -> BrowsePage {
        _ = contentScroll.waitForExistence(timeout: timeout)
        return self
    }

    func tapSearch() -> SearchPage {
        searchTabButton.tap()
        return SearchPage(app: app)
    }

    func tapLibrary() -> LibraryPage {
        libraryTabButton.tap()
        return LibraryPage(app: app)
    }
}
