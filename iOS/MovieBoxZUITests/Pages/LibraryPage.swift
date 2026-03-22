import XCTest

/// Page object for the Library tab.
struct LibraryPage {
    let app: XCUIApplication

    var myListButton: XCUIElement { app.buttons["My List"] }
    var watchedButton: XCUIElement { app.buttons["Watched"] }
    // "My Library" header is always present regardless of whether the list is empty
    var contentArea: XCUIElement { app.staticTexts["My Library"] }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> LibraryPage {
        _ = contentArea.waitForExistence(timeout: timeout)
        return self
    }

    func switchToWatched() -> LibraryPage {
        watchedButton.tap()
        return self
    }

    func switchToMyList() -> LibraryPage {
        myListButton.tap()
        return self
    }
}
