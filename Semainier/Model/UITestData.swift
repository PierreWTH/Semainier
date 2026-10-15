#if DEBUG
import Foundation
import SwiftData

/// Jeu de données minimal pour les tests d'interface (lancement avec `-UITestData`).
enum UITestData {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-UITestData") }

    static func insert(into context: ModelContext) {
        let skyr = Ingredient(name: "Skyr", unit: .g, kcal: 64, p: 11, c: 4, f: 0.2, rayon: .cremerieOeufs)
        context.insert(skyr)
        let r = Recipe(name: "Skyr test")
        context.insert(r)
        let item = RecipeItem(ingredient: skyr, qty: 200, order: 0)
        context.insert(item)
        item.recipe = r
        // Collation du jour courant.
        context.insert(PlanEntry(date: Days.today, slot: 2, recipe: r))
    }
}
#endif
