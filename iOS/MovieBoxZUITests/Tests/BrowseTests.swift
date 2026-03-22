import XCTest

/// Tests for the Browse (home) screen — loading, content, tab navigation.
final class BrowseTests: MovieBoxZUITestCase {

    func testBrowseContentAppearsAfterLoad() {
        let browse = BrowsePage(app: app)
        XCTAssert(browse.contentScroll.waitForExistence(timeout: 15),
                  "Browse content should appear within 15s")
    }

    func testBrowseContainsScrollableContent() {
        let browse = BrowsePage(app: app).waitUntilLoaded()
        XCTAssert(browse.contentScroll.exists)
        XCTAssert(browse.contentScroll.isHittable)
    }

    func testTappingSearchTabShowsSearchField() {
        let browse = BrowsePage(app: app).waitUntilLoaded()
        let search = browse.tapSearch().waitUntilLoaded()
        XCTAssert(search.searchField.exists, "Search field should appear")
    }

    func testTappingLibraryTabShowsLibraryContent() {
        let browse = BrowsePage(app: app).waitUntilLoaded()
        let library = browse.tapLibrary().waitUntilLoaded()
        XCTAssert(library.contentArea.exists, "Library content area should exist")
    }

    func testReturnToBrowseFromSearch() {
        let browse = BrowsePage(app: app).waitUntilLoaded()
        browse.tapSearch()
        browse.tabItem.tap()
        XCTAssert(browse.contentScroll.waitForExistence(timeout: 8),
                  "Browse content should reappear")
    }
}
