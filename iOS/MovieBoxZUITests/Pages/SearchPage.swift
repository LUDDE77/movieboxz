import XCTest

/// Page object for the Search tab.
struct SearchPage {
    let app: XCUIApplication

    // SearchView uses a SwiftUI TextField (not UISearchBar) — must query textFields, not searchFields
    var searchField: XCUIElement { app.textFields.firstMatch }
    // LazyVGrid tagged with accessibilityIdentifier("search.grid.results")
    var resultsGrid: XCUIElement { app.otherElements["search.grid.results"] }
    // Results count label — "N results" — always rendered when results exist
    var resultsCountLabel: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'result' OR label ENDSWITH 'results'")).firstMatch
    }
    var noResultsLabel: XCUIElement { app.staticTexts["No Results"] }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> SearchPage {
        _ = searchField.waitForExistence(timeout: timeout)
        return self
    }

    func typeSearch(_ query: String) -> SearchPage {
        searchField.tap()
        searchField.typeText(query + "\n")  // \n fires .onSubmit to trigger the search API call
        return self
    }

    func clearSearch() -> SearchPage {
        searchField.tap()
        searchField.buttons["Clear text"].tap()
        return self
    }
}
