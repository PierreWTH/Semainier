import Foundation
import Testing
@testable import Semainier

/// Bibliothèque d'aliments bruts (Ciqual) et recherche par nom.
struct FoodLibraryTests {
    @Test func bundledJsonLoads() {
        let list = FoodLibrary.foods
        #expect(list.count > 300)
        #expect(Set(list.map(\.code)).count == list.count)
        #expect(Set(list.map(\.name)).count == list.count)
        #expect(list.allSatisfy { $0.kcal > 0 || ($0.p == 0 && $0.c == 0 && $0.f == 0) })
        let chicken = list.first { $0.name == "Poulet, filet cru" }
        #expect(chicken?.kcal == 110)
        #expect(chicken?.p == 23.4)
        #expect(chicken?.aisle == .meatFish)
    }

    @Test func emptyQueryFindsNothing() {
        #expect(FoodLibrary.search("").isEmpty)
        #expect(FoodLibrary.search("   ").isEmpty)
    }

    @Test func aliasesAndSeveralWords() {
        #expect(FoodLibrary.search("basmati").map(\.name) == ["Riz blanc cru"])
        #expect(FoodLibrary.search("riz basmati").map(\.name) == ["Riz blanc cru"])
        #expect(FoodLibrary.search("olive").map(\.name) == ["Huile"])
    }

    @Test func eggFindsLigature() {
        let names = FoodLibrary.search("oeuf").map(\.name)
        #expect(names.contains("Œuf"))
        #expect(names.contains("Blanc d'œuf"))
        #expect(!names.contains { $0.hasPrefix("Bœuf") })
        #expect(FoodLibrary.search("œuf").map(\.name) == names)
        #expect(Set(FoodLibrary.search("boeuf filet").map(\.name)) == ["Bœuf, filet cru", "Bœuf, faux-filet cru"])
    }

    @Test func savedIngredientIsExcluded() {
        let names = FoodLibrary.search("pomme", excluding: ["  POMME "]).map(\.name)
        #expect(!names.contains("Pomme"))
        #expect(names.contains("Pomme de terre"))
        #expect(!FoodLibrary.search("oeuf", excluding: ["Oeuf"]).map(\.name).contains("Œuf"))
    }

    @Test func prefixMatchesComeFirst() {
        let names = FoodLibrary.search("riz").map(\.name)
        #expect(names.first == "Riz blanc cru")
        let firstOther = names.firstIndex { !$0.hasPrefix("Riz") }
        #expect(firstOther.map { names[$0...].allSatisfy { !$0.hasPrefix("Riz") } } ?? true)
        #expect(names.contains("Farine de riz"))
    }

    @Test func filteredMatchesLigatures() {
        let names = ["Œuf", "Beurre", "Bœuf, filet"]
        #expect(names.filtered("oeuf", name: { $0 }) == ["Œuf"])
        #expect(names.filtered("boeuf", name: { $0 }) == ["Bœuf, filet"])
        #expect(names.filtered("œuf", name: { $0 }) == ["Œuf"])
        #expect(names.filtered("fil", name: { $0 }) == ["Bœuf, filet"])
        #expect(names.filtered("", name: { $0 }) == ["Beurre", "Bœuf, filet", "Œuf"])
    }

    @MainActor @Test func prefilledDraft() {
        let rice = FoodLibrary.foods.first { $0.name == "Riz blanc cru" }!
        let d = IngredientDraft(food: rice)
        #expect(d.name == "Riz blanc cru")
        #expect(d.unit == .g)
        #expect(d.resolvedKcal == 350)
        #expect(d.macros.c == 77.5)
        #expect(d.aisle == .grocery)
    }
}
