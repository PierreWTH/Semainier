import XCTest

/// Feuilles enchaînées depuis « Ajouter » : la suivante s'ouvre quand la précédente a fini de se fermer.
final class AddChainTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestData", "-DisableAnimations", "-tab", "planning", "-planning.mode", "jour"]
        app.launch()
    }

    private func openAddSheet() {
        let add = app.buttons["Ajouter un plat"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Ajouter"].waitForExistence(timeout: 3))
    }

    /// Nouvel ingrédient → enregistré → la saisie de sa quantité s'ouvre → le plat arrive dans la journée.
    func testNewIngredientThenAsksQuantity() {
        openAddSheet()
        app.segmentedControls.buttons["Ingrédients"].tap()
        app.buttons["Nouvel ingrédient"].tap()

        let name = app.textFields["Ex. Flocons d'avoine"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Lentilles")
        app.buttons["Enregistrer"].tap()

        let quantity = app.navigationBars["Lentilles"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 3))
        quantity.buttons["Ajouter"].tap()

        XCTAssertFalse(app.navigationBars["Ajouter"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Lentilles"].waitForExistence(timeout: 3))
    }

    /// Nouvelle recette à la pièce → enregistrée → le nombre de pièces est demandé.
    func testNewPieceRecipeThenAsksCount() {
        openAddSheet()
        app.segmentedControls.buttons["Plats"].tap()
        let create = app.buttons["Créer une nouvelle recette"]
        if !create.waitForExistence(timeout: 2) { app.swipeUp() }
        create.tap()

        let name = app.textFields["Ex. Poulet, riz & brocoli"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Burger test")
        app.switches["Se compte à la pièce"].switches.firstMatch.tap()

        app.buttons["Choisir un ingrédient"].tap()
        let skyr = app.buttons.containing(.staticText, identifier: "Skyr").firstMatch
        XCTAssertTrue(skyr.waitForExistence(timeout: 3))
        skyr.tap()

        let qty = app.textFields["Quantité"]
        XCTAssertTrue(qty.waitForExistence(timeout: 3))
        qty.tap()
        qty.typeText("100")
        app.navigationBars["Nouvelle recette"].buttons["Enregistrer"].tap()

        let count = app.navigationBars["Burger test"]
        XCTAssertTrue(count.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nombre de pièces"].exists || app.staticTexts["NOMBRE DE PIÈCES"].exists)
    }
}
