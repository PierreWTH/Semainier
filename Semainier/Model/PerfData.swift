#if DEBUG
import Foundation
import SwiftData

/// Planning chargé pour mesurer les performances (lancement avec `-PerfData`) : un an d'historique et deux semaines
/// à venir, environ 3 000 plats. Base en mémoire, comme `-UITestData` : jamais les vraies données.
enum PerfData {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-PerfData") }

    static func insert(into context: ModelContext, today: DayKey = Days.today) {
        let specs: [(String, Unit, Double, Double, Double, Double, Rayon)] = [
            ("Flocons d'avoine", .g, 372, 13, 59, 7, .epicerie),
            ("Lait demi-écrémé", .ml, 46, 3.3, 4.8, 1.6, .cremerieOeufs),
            ("Whey", .g, 380, 78, 6, 5, .epicerie),
            ("Banane", .g, 90, 1.1, 20, 0.3, .fruitsLegumes),
            ("Skyr", .g, 64, 11, 4, 0.2, .cremerieOeufs),
            ("Riz basmati", .g, 350, 8, 77, 1, .epicerie),
            ("Blanc de poulet", .g, 110, 23, 0, 1.5, .viandesPoissons),
            ("Brocoli", .g, 34, 2.8, 4, 0.4, .fruitsLegumes),
            ("Pâtes", .g, 357, 12, 71, 1.5, .epicerie),
            ("Bœuf haché 5 %", .g, 125, 21, 0, 5, .viandesPoissons),
            ("Sauce tomate", .g, 45, 1.5, 7, 1, .epicerie),
            ("Œuf", .pc, 75, 6.5, 0.5, 5, .cremerieOeufs),
            ("Pain complet", .g, 240, 9, 41, 3, .boulangerie),
            ("Saumon", .g, 200, 20, 0, 13, .viandesPoissons),
            ("Huile d'olive", .ml, 820, 0, 0, 91, .epicerie),
        ]
        let ings = specs.map { s in
            let i = Ingredient(name: s.0, unit: s.1, kcal: s.2, p: s.3, c: s.4, f: s.5, rayon: s.6)
            context.insert(i)
            return i
        }
        func recipe(_ name: String, _ items: [(Int, Double)], byPiece: Bool = false, batch: Bool = false) -> Recipe {
            let r = Recipe(name: name)
            r.byPiece = byPiece
            r.batch = batch
            context.insert(r)
            for (n, (i, q)) in items.enumerated() {
                let item = RecipeItem(ingredient: ings[i], qty: q, order: n)
                context.insert(item)
                item.recipe = r
            }
            return r
        }
        let breakfasts = [recipe("Porridge", [(0, 80), (1, 250), (3, 100)]),
                          recipe("Shaker Whey Lait", [(2, 30), (1, 300)]),
                          recipe("Tartine œufs", [(12, 80), (11, 2)], byPiece: true)]
        let meals = [recipe("Riz poulet brocoli", [(5, 90), (6, 180), (7, 150), (14, 10)], batch: true),
                     recipe("Pâtes bolo", [(8, 110), (9, 150), (10, 120)], batch: true),
                     recipe("Saumon riz", [(13, 150), (5, 80), (14, 5)])]

        var n = 0
        for offset in -365...14 {
            let day = Days.adding(offset, to: today)
            n += 1
            // Portions de base partout (l'appli ne permet pas d'en régler d'autres) ; la tartine se compte à la pièce.
            let breakfast = breakfasts[n % 3]
            context.insert(PlanEntry(date: day, slot: 0, recipe: breakfast, x: breakfast.byPiece ? 2 : 1))
            context.insert(PlanEntry(date: day, slot: 1, recipe: meals[n % 3]))
            context.insert(PlanEntry(date: day, slot: 2, ingredient: ings[4], qty: 150))
            context.insert(PlanEntry(date: day, slot: 2, ingredient: ings[3], qty: 120, order: 1))
            context.insert(PlanEntry(date: day, slot: 3, recipe: meals[(n + 1) % 3]))
            if n % 7 == 0 {
                context.insert(PlanEntry(date: day, slot: 3, free: FreeMeal(name: "Restaurant", kcal: 1100), order: 1))
            }
            if n % 2 == 0 { context.insert(PlanEntry(date: day, slot: 2, ingredient: ings[11], qty: 2, order: 2)) }
            context.insert(PlanEntry(date: day, slot: 0, ingredient: ings[3], qty: 110, order: 1))
        }
    }
}
#endif
