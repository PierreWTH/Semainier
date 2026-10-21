import XCTest

/// Vue jour : « Ajouter un plat » ouvre la fenêtre d'ajout.
final class DaySwipeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestData", "-DisableAnimations", "-tab", "planning", "-planning.mode", "jour"]
        app.launch()
    }

    private var dayView: XCUIElement {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'jour-'")).firstMatch
    }

    func testTapOnAddOpensSheet() {
        XCTAssertTrue(dayView.waitForExistence(timeout: 5))
        app.buttons["Ajouter un plat"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ajouter"].waitForExistence(timeout: 3))
    }
}
