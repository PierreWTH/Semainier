import XCTest

/// Glisser-déposer et menu contextuel d'un plat dans la vue semaine.
final class WeekDragTests: XCTestCase {
    private var app: XCUIApplication!
    /// La grille commence aujourd'hui : colonne 0 = aujourd'hui, 1 = demain.
    private let today = 0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestData", "-DisableAnimations", "-tab", "planning", "-planning.mode", "semaine", "-semaine.ensemble", "NO"]
        app.launch()
    }

    private let target = 1

    func testLongPressThenDragDuplicatesDishToNeighbourDay() {
        let chip = app.buttons["entry-Skyr test"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["cell-\(today)-2"].buttons["entry-Skyr test"].exists)

        let destination = app.otherElements["cell-\(target)-2"]
        // Comme un doigt : on tient, on glisse lentement, on marque un temps au-dessus de la case.
        chip.press(forDuration: 0.8, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.6)

        XCTAssertTrue(destination.buttons["entry-Skyr test"].waitForExistence(timeout: 3))
        // L'original reste en place : c'est une copie.
        XCTAssertTrue(app.otherElements["cell-\(today)-2"].buttons["entry-Skyr test"].exists)
    }

    func testLongPressWithoutMovingOpensMenu() {
        let chip = app.buttons["entry-Skyr test"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.press(forDuration: 1.2)

        let remove = app.buttons["Retirer"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Voir la recette"].exists)
        XCTAssertTrue(app.buttons["Copier vers"].exists)
        XCTAssertTrue(app.buttons["Déplacer vers"].exists)
        remove.tap()
        XCTAssertFalse(app.buttons["entry-Skyr test"].waitForExistence(timeout: 2))
    }

    func testPullingPastFirstDayShowsPreviousWeek() {
        let todayCell = app.otherElements["cell-0-2"]
        XCTAssertTrue(todayCell.buttons["entry-Skyr test"].waitForExistence(timeout: 5))

        // On tire la grille vers la droite au-delà du premier jour, dans le rebond, puis on lâche.
        let start = app.otherElements["cell-0-0"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 330, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        // La grille passe à la semaine précédente, calée sur son dernier jour (colonne 6).
        XCTAssertTrue(app.otherElements["cell-6-0"].waitForExistence(timeout: 3))

        // Le bouton du jour (« Ven 23 ») ramène sur la semaine d'aujourd'hui : aujourd'hui redevient la première colonne.
        let todayButton = app.buttons["today"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 2))
        todayButton.tap()
        XCTAssertTrue(app.otherElements["cell-0-2"].buttons["entry-Skyr test"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["cell-7-2"].exists)
        XCTAssertFalse(todayButton.exists)
    }
}
