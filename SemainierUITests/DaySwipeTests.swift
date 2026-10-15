import XCTest

/// Balayer la vue jour change de jour, même en partant d'un bouton.
final class DaySwipeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestData", "-tab", "planning", "-planning.mode", "jour"]
        app.launch()
    }

    private var dayView: XCUIElement {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'jour-'")).firstMatch
    }

    func testSwipeFromAddButtonChangesDayWithoutOpeningSheet() {
        XCTAssertTrue(dayView.waitForExistence(timeout: 5))
        let today = dayView.identifier

        // Balayage vers la gauche qui part du bouton « Ajouter un plat ».
        let add = app.buttons["Ajouter un plat"].firstMatch
        XCTAssertTrue(add.exists)
        add.swipeLeft()

        expectation(for: NSPredicate(format: "identifier != %@", today), evaluatedWith: dayView)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.navigationBars["Ajouter"].exists, "le bouton ne doit pas s'être déclenché")

        // Et retour vers la droite.
        dayView.swipeRight()
        expectation(for: NSPredicate(format: "identifier == %@", today), evaluatedWith: dayView)
        waitForExpectations(timeout: 3)
    }

    func testSimpleTapOnAddStillOpensSheet() {
        XCTAssertTrue(dayView.waitForExistence(timeout: 5))
        app.buttons["Ajouter un plat"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ajouter"].waitForExistence(timeout: 3))
    }
}
