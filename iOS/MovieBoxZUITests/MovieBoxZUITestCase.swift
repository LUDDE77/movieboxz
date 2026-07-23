import XCTest

/// Base class for all MovieBoxZ UI tests.
/// Launches the app with the welcome screen bypassed so ContentView/TabView is always shown.
class MovieBoxZUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Subclasses can add launch arguments (e.g. the screenshot demo flag).
    var extraLaunchArguments: [String] { [] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING_SKIP_WELCOME"] + extraLaunchArguments
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }
}
