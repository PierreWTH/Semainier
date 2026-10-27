import Foundation
import SwiftData
import Testing
@testable import Semainier

/// Logique sortie des écrans : liste de courses, « À préparer », semaines, statistiques de la semaine.
@MainActor
struct ShoppingPrepTests {
    let context: ModelContext
    let rice: Ingredient, chicken: Ingredient, skyr: Ingredient, egg: Ingredient

    init() throws {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        rice = Ingredient(name: "Riz", unit: .g, kcal: 350, p: 8, c: 77, f: 1, aisle: .grocery)
        chicken = Ingredient(name: "Poulet", unit: .g, kcal: 110, p: 23, c: 0, f: 1.5, aisle: .meatFish)
        skyr = Ingredient(name: "Skyr", unit: .g, kcal: 64, p: 11, c: 4, f: 0.2, aisle: .dairyEggs)
        egg = Ingredient(name: "Œuf", unit: .pc, kcal: 75, p: 6.5, c: 0.5, f: 5, aisle: .dairyEggs)
        [rice, chicken, skyr, egg].forEach(context.insert)
    }

    private func recipe(_ name: String, _ items: [(Ingredient, Double)], batch: Bool = false) -> Recipe {
        let r = Recipe(name: name)
        r.batch = batch
        context.insert(r)
        for (n, (g, q)) in items.enumerated() {
            let it = RecipeItem(ingredient: g, qty: q, order: n)
            context.insert(it)
            it.recipe = r
        }
        return r
    }

    private func entries() throws -> [PlanEntry] { try context.fetch(FetchDescriptor<PlanEntry>()) }

    // MARK: Liste de courses

    @Test func shoppingSumsChosenDaysOnly() throws {
        let r = recipe("Riz poulet", [(rice, 90), (chicken, 150)])
        PlanActions.add(r, x: 1.5, date: 20261026, slot: .lunch, in: context)
        PlanActions.add(r, date: 20261027, slot: .dinner, in: context)
        PlanActions.add(skyr, qty: 150, date: 20261027, slot: .snack, in: context)
        PlanActions.add(r, date: 20261030, slot: .dinner, in: context)          // jour non choisi
        PlanActions.add(FreeMeal(name: "Pizza", kcal: 900), date: 20261026, slot: .dinner, in: context)

        let list = ShoppingList(entries: try entries(), days: [20261026, 20261027])
        let qty = Dictionary(uniqueKeysWithValues: list.lines.map { ($0.ingredient.name, $0.qty) })
        #expect(qty == ["Riz": 225, "Poulet": 375, "Skyr": 150])   // repas libre absent
    }

    @Test func shoppingSectionsPutCheckedLast() throws {
        PlanActions.add(skyr, qty: 150, date: 20261026, slot: .snack, in: context)
        PlanActions.add(egg, qty: 2, date: 20261026, slot: .breakfast, in: context)
        PlanActions.add(rice, qty: 80, date: 20261026, slot: .lunch, in: context)
        let list = ShoppingList(entries: try entries(), days: [20261026])

        let sections = list.byAisle(checkedKeys: [skyr.uid])
        // Ordre du magasin : crèmerie avant épicerie ; dans la crèmerie, le skyr coché passe après l'œuf.
        #expect(sections.map(\.aisle) == [.dairyEggs, .grocery])
        #expect(sections[0].lines.map(\.ingredient.name) == ["Œuf", "Skyr"])

        let text = list.text(checkedKeys: [skyr.uid], days: "7 prochains jours")
        #expect(text == "Liste de courses (7 prochains jours)\n\nCrèmerie & œufs\n- Œuf : 2 pièces\n\nÉpicerie\n- Riz : 80 g")
    }

    @Test func shoppingDaysText() {
        #expect(ShoppingList.daysText([0, 1, 2, 3, 4, 5, 6], today: 20261026) == "7 prochains jours")
        #expect(ShoppingList.daysText([1, 0], today: 20261026) == "Lun 26, Mar 27")
    }

    // MARK: À préparer

    @Test func prepCountsPortionsAndKeepsRecipeOrder() throws {
        let bolo = recipe("Bolo", [(rice, 100), (chicken, 120)], batch: true)
        let shaker = recipe("Shaker", [(skyr, 200)])
        PlanActions.add(bolo, x: 1.2, date: 20261026, slot: .lunch, in: context)
        PlanActions.add(bolo, date: 20261026, slot: .dinner, in: context)
        PlanActions.add(bolo, date: 20261028, slot: .dinner, in: context)
        PlanActions.add(shaker, date: 20261026, slot: .snack, in: context)

        let days: Set<DayKey> = [20261026, 20261027, 20261028]
        let preps = Preparation.toPrepare(try entries(), days: days)
        #expect(preps.count == 1)                                  // le shaker ne se prépare pas à l'avance
        let p = try #require(preps.first)
        #expect(abs(p.total - 3.2) < 1e-9)
        #expect(p.lines.map(\.ingredient.name) == ["Riz", "Poulet"])
        #expect(abs(p.lines[0].qty - 320) < 1e-9)
        #expect(p.daysText(chosenCount: days.count) == "lun ×2, mer")
        #expect(Preparation.dishes(try entries(), days: days, batch: false).map(\.recipe.name) == ["Shaker"])
    }

    @Test func prepSortsByPortionsThenName() throws {
        let a = recipe("Lasagnes", [(rice, 100)], batch: true)
        let b = recipe("Chili", [(rice, 100)], batch: true)
        let c = recipe("Curry", [(rice, 100)], batch: true)
        PlanActions.add(a, date: 20261026, slot: .dinner, in: context)
        PlanActions.add(b, x: 2, date: 20261026, slot: .lunch, in: context)
        PlanActions.add(c, date: 20261027, slot: .dinner, in: context)
        let names = Preparation.toPrepare(try entries(), days: [20261026, 20261027]).map(\.recipe.name)
        #expect(names == ["Chili", "Curry", "Lasagnes"])
        #expect(Preparation.toPrepare(try entries(), days: [20261026, 20261027], query: "cur").map(\.recipe.name) == ["Curry"])
    }

    @Test func prepEveryDayText() throws {
        let r = recipe("Porridge", [(rice, 50)], batch: true)
        let days = Days.range(from: 20261026, count: 7)
        for d in days { PlanActions.add(r, date: d, slot: .breakfast, in: context) }
        let p = try #require(Preparation.toPrepare(try entries(), days: Set(days)).first)
        #expect(p.daysText(chosenCount: 7) == "tous les jours")
    }
}

struct WeekTests {
    @Test func weekContainingDay() {
        // Semaines de 7 jours à partir du dimanche 25 octobre 2026.
        #expect(Days.weekStart(containing: 20261025, home: 20261025) == 20261025)
        #expect(Days.weekStart(containing: 20261031, home: 20261025) == 20261025)
        #expect(Days.weekStart(containing: 20261101, home: 20261025) == 20261101)
        #expect(Days.weekStart(containing: 20261024, home: 20261025) == 20261018)   // la veille : semaine d'avant
    }

    @Test func chosenDays() {
        #expect(Days.chosen([0, 2, 6], from: 20261030) == [20261030, 20261101, 20261105])
    }

    @Test func weekStatsIgnoreEmptyDays() {
        let s = Nutrition.weekStats([2600, 0, 2000, 2650, 0, 0, 3000], target: 2600)
        #expect(s.average == 2562.5)
        #expect(s.withinTarget == 2)
        #expect(!s.empty)
        #expect(Nutrition.weekStats([0, 0], target: 2600) == WeekStats(average: 0, withinTarget: 0, empty: true))
    }
}
