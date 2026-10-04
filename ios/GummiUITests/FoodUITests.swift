import XCTest

/// Taps like a finger would, for the controls the Simulator can't tap from a script.
nonisolated final class FoodUITests: XCTestCase {
    @MainActor
    func testPlusOpensLogFood() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-gummi.mode", "mock", "-gummi.noPrompts", "YES", "-gummi.tab", "food"]
        app.launch()
        let plus = app.buttons["Log food"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5), "Log food sheet didn't open")
        // The name field has focus when the sheet opens.
        app.typeText("apple")
        app.navigationBars["Log food"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "apple")).firstMatch.waitForExistence(timeout: 8),
                      "The logged apple didn't show up in the food log")
    }
}
