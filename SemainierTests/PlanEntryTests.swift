import Foundation
import SwiftData
import Testing
@testable import Semainier

@MainActor
struct PlanEntryTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func skyr() -> Ingredient {
        let i = Ingredient(name: "Skyr", unit: .g, kcal: 64, p: 11, c: 4, f: 0.2, rayon: .cremerieOeufs)
        context.insert(i)
        return i
    }

    @Test func ingredientEntryTotalsAndShopping() {
        let i = skyr()
        PlanActions.add(i, qty: 250, date: 20261014, slot: .collation, in: context)
        let e = try! context.fetch(FetchDescriptor<PlanEntry>()).first!
        #expect(e.title == "Skyr")
        #expect(e.totals.kcal == 160)                   // kcal de l'étiquette : 250 g × 64 / 100
        #expect(e.shoppingLines.count == 1)
        #expect(e.shoppingLines[0].qty == 250)
    }

    @Test func copyDayKeepsIngredientEntries() throws {
        let i = skyr()
        PlanActions.add(i, qty: 150, date: 20261012, slot: .collation, in: context)
        PlanActions.copy(day: 20261012, to: [20261015], in: context)
        let copied = try context.fetch(FetchDescriptor<PlanEntry>()).filter { $0.date == 20261015 }
        #expect(copied.count == 1)
        #expect(copied[0].ingredient?.name == "Skyr" && copied[0].qty == 150)
    }

    @Test func deletingIngredientRemovesItFromPlan() throws {
        let i = skyr()
        PlanActions.add(i, qty: 100, date: 20261013, slot: .petitDejeuner, in: context)
        try context.save()
        PlanActions.delete(i, settings: PlanActions.settings(in: context), in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<PlanEntry>()).isEmpty)
    }

    @Test func backupRoundTripWithIngredientEntry() throws {
        let i = skyr()
        PlanActions.add(i, qty: 200, date: 20261016, slot: .diner, in: context)
        try context.save()
        let data = try JSONEncoder().encode(Backup.make(from: context))
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        #expect(backup.plan.first?.ing == i.uid && backup.plan.first?.qty == 200)

        try backup.restore(into: context)
        let restored = try context.fetch(FetchDescriptor<PlanEntry>())
        #expect(restored.count == 1)
        #expect(restored[0].ingredient?.name == "Skyr" && restored[0].qty == 200 && restored[0].date == 20261016)
    }

    @Test func loneIngredientsBecomeOneRecipeDish() throws {
        let i = skyr()
        let other = Ingredient(name: "Banane", unit: .g, kcal: 90, p: 1, c: 20, f: 0.3, rayon: .fruitsLegumes)
        context.insert(other)
        PlanActions.add(i, qty: 150, date: 20261020, slot: .petitDejeuner, in: context)
        PlanActions.add(other, qty: 120, date: 20261020, slot: .petitDejeuner, in: context)
        let lone = try context.fetch(FetchDescriptor<PlanEntry>()).sorted { $0.order < $1.order }
        lone[1].x = 2
        let kcalBefore = lone.map(\.totals).sum.kcal

        let r = Recipe(name: "Bol skyr banane")
        context.insert(r)
        for (n, (g, q)) in LoneToRecipe(entries: lone).prefill.enumerated() {
            let item = RecipeItem(ingredient: g, qty: q, order: n)
            context.insert(item)
            item.recipe = r
        }
        PlanActions.replace(lone, with: r, in: context)
        try context.save()

        let left = try context.fetch(FetchDescriptor<PlanEntry>())
        #expect(left.count == 1)
        #expect(left[0].recipe?.name == "Bol skyr banane" && left[0].slot == 0 && left[0].date == 20261020)
        #expect(abs(left[0].totals.kcal - kcalBefore) < 0.001)   // portion ×2 reprise dans la recette
    }

    @Test func pieceRecipeMultipliesAndSurvivesBackup() throws {
        let i = skyr()
        let r = Recipe(name: "Burger")
        r.byPiece = true
        r.batch = true
        context.insert(r)
        let item = RecipeItem(ingredient: i, qty: 100, order: 0)
        context.insert(item)
        item.recipe = r
        PlanActions.add(r, x: 2, date: 20261021, slot: .diner, in: context)
        let e = try #require(try context.fetch(FetchDescriptor<PlanEntry>()).first)
        #expect(e.totals.kcal == 128)                   // 2 × 64
        #expect(e.shoppingLines.first?.qty == 200)
        #expect(Fmt.pieces(e.x) == "2 pièces" && Fmt.pieces(1) == "1 pièce")
        try context.save()

        let data = try JSONEncoder().encode(Backup.make(from: context))
        try JSONDecoder().decode(Backup.self, from: data).restore(into: context)
        let restored = try #require(try context.fetch(FetchDescriptor<PlanEntry>()).first)
        #expect(restored.recipe?.byPiece == true && restored.recipe?.batch == true && restored.x == 2)
    }

    @Test func freeMealCountsKcalButNotShopping() throws {
        PlanActions.add(FreeMeal(name: "Pizza", kcal: 1200), date: 20261017, slot: .diner, in: context)
        let e = try #require(try context.fetch(FetchDescriptor<PlanEntry>()).first)
        #expect(e.isValid && e.isFree)
        #expect(e.title == "Pizza")
        #expect(e.totals == Macros(kcal: 1200))       // sans macros précisées
        #expect(e.shoppingLines.isEmpty)
        #expect(e.free?.hasMacros == false)
    }

    @Test func freeMealCopyAndBackupKeepValues() throws {
        let meal = FreeMeal(name: "Burger", kcal: 950, p: 40, c: 80, f: 50)
        PlanActions.add(meal, date: 20261018, slot: .dejeuner, in: context)
        let e = try #require(try context.fetch(FetchDescriptor<PlanEntry>()).first)
        PlanActions.duplicate(e, date: 20261019, slot: .diner, in: context)
        try context.save()

        let data = try JSONEncoder().encode(Backup.make(from: context))
        try JSONDecoder().decode(Backup.self, from: data).restore(into: context)
        let restored = try context.fetch(FetchDescriptor<PlanEntry>()).sorted { $0.date < $1.date }
        #expect(restored.count == 2)
        #expect(restored.allSatisfy { $0.free == meal })
        #expect(restored.map(\.date) == [20261018, 20261019])
        #expect(restored[0].totals == Macros(kcal: 950, p: 40, c: 80, f: 50))
    }
}

@MainActor
struct OverrideTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    /// Recette « Riz poulet » : 100 g de riz (350 kcal/100 g) + 150 g de poulet (110 kcal/100 g).
    private func setup() -> (PlanEntry, RecipeItem, Recipe) {
        let riz = Ingredient(name: "Riz", unit: .g, kcal: 350, p: 7, c: 78, f: 1, rayon: .epicerie)
        let poulet = Ingredient(name: "Poulet", unit: .g, kcal: 110, p: 23, c: 0, f: 2, rayon: .viandesPoissons)
        let r = Recipe(name: "Riz poulet")
        [riz, poulet].forEach(context.insert)
        context.insert(r)
        let a = RecipeItem(ingredient: riz, qty: 100, order: 0), b = RecipeItem(ingredient: poulet, qty: 150, order: 1)
        [a, b].forEach { context.insert($0); $0.recipe = r }
        let e = PlanEntry(date: 20261014, slot: 1, recipe: r)
        context.insert(e)
        return (e, a, r)
    }

    @Test func overrideChangesOnlyThisDish() {
        let (e, riz, r) = setup()
        #expect(e.totals.kcal == 515)                   // riz 350 + poulet 165
        e.setQty(150, for: riz)
        #expect(e.isOverridden(riz))
        #expect(e.totals.kcal == 690)                   // 525 + 165
        #expect(r.totals.kcal == 515)                   // la recette n'a pas changé
        #expect(e.shoppingLines.first { $0.ingredient.name == "Riz" }?.qty == 150)
    }

    @Test func overrideIsPerPortion() {
        let (e, riz, _) = setup()
        e.x = 2
        e.setQty(300, for: riz)                  // quantité affichée, portion comprise
        #expect(e.qty(for: riz) == 150)
        #expect(e.shoppingLines.first { $0.ingredient.name == "Riz" }?.qty == 300)
    }

    @Test func sameQtyOrResetClearsOverride() {
        let (e, riz, _) = setup()
        e.setQty(120, for: riz)
        e.setQty(100, for: riz)
        #expect(!e.isOverridden(riz))
        e.setQty(120, for: riz)
        e.resetQty(for: riz)
        #expect(e.overrides.isEmpty)
    }

    @Test func copyKeepsOverrides() {
        let (e, riz, _) = setup()
        e.setQty(150, for: riz)
        #expect(e.copy(to: 4)?.qty(for: riz) == 150)
    }

    @Test func backupKeepsOverrides() throws {
        let (e, riz, _) = setup()
        e.setQty(150, for: riz)
        try context.save()
        let data = try JSONEncoder().encode(Backup.make(from: context))
        try JSONDecoder().decode(Backup.self, from: data).restore(into: context)
        let restored = try context.fetch(FetchDescriptor<PlanEntry>())
        #expect(restored.count == 1)
        #expect(restored[0].totals.kcal == 690)
    }
}

@MainActor
struct TargetsTests {
    @Test func kcalFollowsMacros() {
        let s = AppSettings()
        s.targetC = 400 // 400×4 + 160×4 + 80×9 = 2960
        s.syncKcalWithMacros()
        #expect(s.targetKcal == 2960)
    }

    @Test func defaultTargetsAreConsistent() {
        let s = AppSettings()
        s.syncKcalWithMacros()
        #expect(s.targetKcal == 2600)
    }
}

@MainActor
struct MoveTests {
    @Test func moveGoesToEndOfTargetCell() throws {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let r = Recipe(name: "Skyr")
        context.insert(r)
        PlanActions.add(r, date: 20261016, slot: .collation, in: context)   // déjà un plat le vendredi
        PlanActions.add(r, date: 20261015, slot: .collation, in: context)
        let thursday = try context.fetch(FetchDescriptor<PlanEntry>()).first { $0.date == 20261015 }!
        PlanActions.move(thursday, date: 20261016, slot: .collation, in: context)
        #expect(thursday.date == 20261016 && thursday.slot == 2 && thursday.order == 1)
    }

    @Test func duplicateKeepsOriginalAndCopiesOverrides() throws {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let skyr = Ingredient(name: "Skyr", unit: .g, kcal: 64, p: 11, c: 4, f: 0.2, rayon: .cremerieOeufs)
        let r = Recipe(name: "Bol")
        context.insert(skyr); context.insert(r)
        let it = RecipeItem(ingredient: skyr, qty: 200, order: 0)
        context.insert(it); it.recipe = r
        let e = PlanEntry(date: 20261015, slot: 0, recipe: r, x: 1.5)
        context.insert(e)
        e.setQty(450, for: it)                       // 300 g par portion
        PlanActions.duplicate(e, date: 20261016, slot: .petitDejeuner, in: context)
        let all = try context.fetch(FetchDescriptor<PlanEntry>())
        #expect(all.count == 2)
        let copy = all.first { $0.date == 20261016 }!
        #expect(copy.slot == 0 && copy.x == 1.5 && copy.qty(for: it) == 300)
        #expect(e.date == 20261015)
    }
}

@MainActor
struct DatedMigrationTests {
    @Test func legacyWeekdaysGoToNextSevenDays() throws {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let r = Recipe(name: "Porridge")
        context.insert(r)
        for weekday in [0, 3, 6] {                      // lundi, jeudi, dimanche (ancien modèle)
            let e = PlanEntry(date: 0, slot: 0, recipe: r)
            e.day = weekday
            context.insert(e)
        }
        PlanActions.migrateLegacyDays(in: context, today: 20261015)   // jeudi 15
        let dates = try context.fetch(FetchDescriptor<PlanEntry>()).map(\.date).sorted()
        #expect(dates == [20261015, 20261018, 20261019])
    }

    @Test func oldBackupWithWeekdaysIsPlacedFromToday() throws {
        let json = """
        {"ingredients":[{"id":"a","name":"Riz","unit":"g","kcal":355,"p":8,"c":78,"f":0.9,"rayon":"Épicerie"}],
         "recipes":[{"id":"r","name":"Riz","items":[{"ing":"a","qty":90}]}],
         "plan":[{"id":"e","day":0,"slot":1,"recipe":"r","x":1}],"shopDays":[0],"checked":{}}
        """
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try JSONDecoder().decode(Backup.self, from: Data(json.utf8)).restore(into: context, today: 20261015)
        #expect(try context.fetch(FetchDescriptor<PlanEntry>()).first?.date == 20261019)
    }
}

@MainActor
struct MacroKcalTests {
    @Test func plannedKcalComeFromLabel() {
        // Le planning compte les kcal de l'étiquette ; une fiche incohérente est signalée.
        let stMoret = Ingredient(name: "St Moret", unit: .g, kcal: 765, p: 10, c: 5, f: 8, rayon: .cremerieOeufs)
        #expect(stMoret.macros(qty: 100).kcal == 765)
        #expect(stMoret.kcalLooksOff)
    }

    @Test func missingLabelKcalFallsBackToMacros() {
        let i = Ingredient(name: "Sans kcal", unit: .g, kcal: 0, p: 10, c: 5, f: 8, rayon: .autre)
        #expect(i.macros(qty: 100).kcal == 132)
    }

    @Test func perfectMacrosHitTargetExactly() {
        // 273 g G · 200 g P · 79 g L = 2 603 kcal, l'objectif.
        let m = Macros(p: 200, c: 273, f: 79)
        #expect(m.kcalFromMacros == 2603)
    }
}
