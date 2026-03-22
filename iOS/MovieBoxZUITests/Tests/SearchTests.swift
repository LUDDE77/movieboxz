import XCTest

/// Tests for the Search screen — field interaction and results.
final class SearchTests: MovieBoxZUITestCase {

    private func openSearch() -> SearchPage {
        _ = app.buttons["Browse"].waitForExistence(timeout: 10)
        app.buttons["Search"].tap()
        return SearchPage(app: app).waitUntilLoaded()
    }

    func testSearchFieldExists() {
        let search = openSearch()
        XCTAssert(search.searchField.exists, "Search field must be present")
    }

    func testSearchFieldAcceptsInput() {
        let search = openSearch()
        search.searchField.tap()
        search.searchField.typeText("action")
        // typeText dispatches keystrokes async relative to SwiftUI binding — wait for full value
        let predicate = NSPredicate(format: "value == 'action'")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: search.searchField)
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(search.searchField.value as? String, "action")
    }

    func testSearchReturnsResults() {
        let search = openSearch()
        search.typeSearch("action")
        // Wait for "N results" label — appears as soon as API returns data
        XCTAssert(
            search.resultsCountLabel.waitForExistence(timeout: 20),
            "Results count label should appear after searching (e.g. '12 results')"
        )
    }
}
