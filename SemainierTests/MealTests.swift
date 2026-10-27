import Foundation
import SwiftData
import Testing
@testable import Semainier

struct MealTests {
    @Test func namesAndOrder() {
        #expect(Meal.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(Meal.allCases.map(\.name) == ["Petit-déjeuner", "Déjeuner", "Collation", "Dîner"])
        #expect(Meal.snack.complement == "de la collation")
        #expect(Meal.dinner.complement == "du dîner")
        #expect(Meal.breakfast.complement == "du petit-déjeuner")
    }

    @Test func outOfRangeSlotIsClamped() {
        #expect(Meal(slot: -1) == .breakfast)
        #expect(Meal(slot: 7) == .dinner)
    }
}

@MainActor
struct PlanEntryKindTests {
    @Test func kindFollowsContent() throws {
        let container = try ModelContainer(for: PlanEntry.self, Recipe.self, Ingredient.self, RecipeItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let g = Ingredient(name: "Skyr", unit: .g, kcal: 64, p: 11, c: 4, f: 0.2, aisle: .dairyEggs)
        context.insert(g)
        let e = PlanEntry(date: 20261015, slot: 2, ingredient: g, qty: 150)
        context.insert(e)
        guard case .ingredient(let i, let q) = e.kind else { Issue.record("ingrédient attendu"); return }
        #expect(i.name == "Skyr" && q == 150)
        #expect(e.meal == .snack)

        let free = PlanEntry(date: 20261015, slot: 3, free: FreeMeal(name: "Pizza", kcal: 900))
        context.insert(free)
        guard case .freeMeal(let m) = free.kind else { Issue.record("repas libre attendu"); return }
        #expect(m.kcal == 900)
    }
}
