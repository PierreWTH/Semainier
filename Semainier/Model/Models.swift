import Foundation
import SwiftData

// Toutes les propriétés ont une valeur par défaut et toutes les relations sont
// optionnelles : c'est ce que CloudKit exige, pour pouvoir activer la sync plus tard.

@Model
final class Ingredient {
    var uid: String = UUID().uuidString
    var name: String = ""
    var unitRaw: String = Unit.g.rawValue
    var kcal: Double = 0
    var p: Double = 0
    var c: Double = 0
    var f: Double = 0
    var rayonRaw: String = Aisle.grocery.rawValue
    var barcode: String?
    /// Poids (ou volume) d'une pièce en g/ml, 0 si inconnu.
    var pieceWeight: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \RecipeItem.ingredient)
    var usages: [RecipeItem]? = []

    // Supprimer un ingrédient le retire aussi du planning quand il y est placé seul.
    @Relationship(deleteRule: .cascade, inverse: \PlanEntry.ingredient)
    var planEntries: [PlanEntry]? = []

    init(name: String, unit: Unit, kcal: Double, p: Double, c: Double, f: Double,
         aisle: Aisle, barcode: String? = nil) {
        self.name = name
        self.unitRaw = unit.rawValue
        self.kcal = kcal
        self.p = p
        self.c = c
        self.f = f
        self.rayonRaw = aisle.rawValue
        self.barcode = barcode
    }

    var unit: Unit {
        get { Unit(rawValue: unitRaw) ?? .g }
        set { unitRaw = newValue.rawValue }
    }

    var aisle: Aisle {
        get { Aisle(rawValue: rayonRaw) ?? .other }
        set { rayonRaw = newValue.rawValue }
    }

    /// Kcal estimées depuis les macros (4 × G + 4 × P + 9 × L) : contrôle et secours.
    var macroKcal: Double { Macros(p: p, c: c, f: f).kcalFromMacros }

    /// Valeurs servant à tous les calculs : kcal de l'étiquette, ou estimation 4/4/9 si elles manquent.
    var per: Macros { Macros(kcal: kcal > 0 ? kcal : macroKcal, p: p, c: c, f: f) }

    /// Kcal de l'étiquette incohérentes avec les macros (fiche probablement fausse).
    var kcalLooksOff: Bool { Nutrition.kcalLooksOff(kcal: kcal, macroKcal: macroKcal) }

    func macros(qty: Double) -> Macros {
        Nutrition.macros(per: per, unit: unit, qty: qty)
    }

    /// Nombre de recettes qui utilisent cet ingrédient.
    var recipeCount: Int {
        Set((usages ?? []).compactMap { $0.recipe?.persistentModelID }).count
    }

    /// Nombre de fois où il est placé seul dans le planning.
    var planCount: Int { planEntries?.count ?? 0 }
}

extension Ingredient {
    /// Ingrédients filtrés par `query` et triés par nom, en une section par rayon, dans l'ordre du magasin
    /// (rayons vides omis).
    static func byAisle(_ list: [Ingredient], query: String) -> [(aisle: Aisle, items: [Ingredient])] {
        let found = list.filtered(query, name: \.name)
        return Aisle.allCases.compactMap { aisle in
            let items = found.filter { $0.aisle == aisle }
            return items.isEmpty ? nil : (aisle, items)
        }
    }
}

@Model
final class Recipe {
    var uid: String = UUID().uuidString
    var name: String = ""
    /// Se compte à la pièce (burger) plutôt qu'à la portion (pâtes) : les quantités sont pour 1 pièce,
    /// et le multiplicateur d'un plat au planning est un nombre de pièces.
    var byPiece = false
    /// Se prépare à l'avance (batch cooking) : le plat apparaît dans Cuisine › « À préparer ».
    /// Un shaker ou une tartine se font au moment : non par défaut.
    var batch = false

    @Relationship(deleteRule: .cascade, inverse: \RecipeItem.recipe)
    var items: [RecipeItem]? = []

    // Supprimer une recette la retire aussi du planning.
    @Relationship(deleteRule: .cascade, inverse: \PlanEntry.recipe)
    var entries: [PlanEntry]? = []

    init(name: String) {
        self.name = name
    }

    var sortedItems: [RecipeItem] {
        (items ?? []).sorted { $0.order < $1.order }
    }

    /// Totaux pour 1 portion (ou 1 pièce).
    var totals: Macros {
        (items ?? []).map(\.macros).sum
    }

    /// Nombre de fois où la recette est au planning (jours passés compris).
    var uses: Int { entries?.count ?? 0 }

    /// Nombre de fois où elle est prévue sur les 7 prochains jours.
    var upcomingUses: Int {
        let today = Days.today, end = Days.adding(7, to: today)
        return (entries ?? []).filter { $0.date >= today && $0.date < end }.count
    }
}

@Model
final class RecipeItem {
    var qty: Double = 0
    var order: Int = 0
    var recipe: Recipe?
    var ingredient: Ingredient?

    init(ingredient: Ingredient, qty: Double, order: Int) {
        self.ingredient = ingredient
        self.qty = qty
        self.order = order
    }

    var macros: Macros { ingredient?.macros(qty: qty) ?? .zero }
}

@Model
final class PlanEntry {
    var uid: String = UUID().uuidString
    /// Date du plat (AAAAMMJJ). 0 = ancienne donnée pas encore migrée.
    var date: DayKey = 0
    /// Ancien modèle « semaine type » (0 = lundi) : ne sert plus qu'à la migration.
    var day: Int = 0
    /// 0 petit-déj, 1 déjeuner, 2 collation, 3 dîner.
    var slot: Int = 0
    /// Multiplicateur de portion (1 = portion de base).
    var x: Double = 1
    var order: Int = 0
    /// Une entrée est soit une recette, soit un ingrédient seul avec sa quantité,
    /// soit un repas libre (nom et kcal estimées, macros facultatives).
    var recipe: Recipe?
    var ingredient: Ingredient?
    /// Quantité de l'ingrédient seul (g, ml ou pièces).
    var qty: Double = 0
    /// Quantités modifiées pour ce plat uniquement (uid de l'ingrédient → quantité pour 1 portion).
    /// La recette elle-même n'est pas touchée.
    var overrides: [String: Double] = [:]
    /// Repas libre : son nom (nil pour une recette ou un ingrédient) et ses valeurs estimées.
    var freeName: String?
    var freeKcal: Double = 0
    var freeP: Double = 0
    var freeC: Double = 0
    var freeF: Double = 0

    init(date: DayKey, slot: Int, recipe: Recipe, x: Double = 1, order: Int = 0) {
        self.date = date
        self.slot = slot
        self.recipe = recipe
        self.x = x
        self.order = order
    }

    init(date: DayKey, slot: Int, ingredient: Ingredient, qty: Double, x: Double = 1, order: Int = 0) {
        self.date = date
        self.slot = slot
        self.ingredient = ingredient
        self.qty = qty
        self.x = x
        self.order = order
    }

    init(date: DayKey, slot: Int, free: FreeMeal, order: Int = 0) {
        self.date = date
        self.slot = slot
        self.order = order
        self.free = free
    }

    /// Ce qu'est le plat : une recette, un ingrédient seul ou un repas libre (dans cet ordre de priorité).
    enum Kind {
        case recipe(Recipe)
        case ingredient(Ingredient, qty: Double)
        case freeMeal(FreeMeal)
        /// Recette ou ingrédient supprimé : l'entrée ne compte plus.
        case empty
    }

    var kind: Kind {
        if let recipe { return .recipe(recipe) }
        if let ingredient { return .ingredient(ingredient, qty: qty) }
        if let free { return .freeMeal(free) }
        return .empty
    }

    var meal: Meal {
        get { Meal(slot: slot) }
        set { slot = newValue.rawValue }
    }

    var title: String { recipe?.name ?? ingredient?.name ?? freeName ?? "" }
    var isValid: Bool { recipe != nil || ingredient != nil || freeName != nil }
    var isFree: Bool { recipe == nil && ingredient == nil && freeName != nil }

    /// Valeurs du repas libre ; nil pour une recette ou un ingrédient.
    var free: FreeMeal? {
        get { isFree ? FreeMeal(name: freeName ?? "", kcal: freeKcal, p: freeP, c: freeC, f: freeF) : nil }
        set {
            freeName = newValue?.name
            freeKcal = newValue?.kcal ?? 0
            freeP = newValue?.p ?? 0
            freeC = newValue?.c ?? 0
            freeF = newValue?.f ?? 0
        }
    }

    /// Quantité d'une ligne de la recette pour 1 portion, en tenant compte des modifications de ce plat.
    func qty(for item: RecipeItem) -> Double {
        item.ingredient.flatMap { overrides[$0.uid] } ?? item.qty
    }

    func isOverridden(_ item: RecipeItem) -> Bool {
        item.ingredient.map { overrides[$0.uid] != nil } ?? false
    }

    /// Fixe la quantité affichée (portion comprise) d'une ligne ; revient à la recette si elle est identique.
    func setQty(_ shown: Double, for item: RecipeItem) {
        guard let uid = item.ingredient?.uid, x > 0 else { return }
        let perPortion = shown / x
        if abs(perPortion - item.qty) < 0.001 { overrides[uid] = nil } else { overrides[uid] = perPortion }
    }

    func resetQty(for item: RecipeItem) {
        if let uid = item.ingredient?.uid { overrides[uid] = nil }
    }

    var totals: Macros {
        switch kind {
        case .recipe(let r): (r.items ?? []).map { $0.ingredient?.macros(qty: qty(for: $0)) ?? .zero }.sum * x
        case .ingredient(let g, let q): g.macros(qty: q) * x
        case .freeMeal(let m): Macros(kcal: m.kcal, p: m.p, c: m.c, f: m.f)
        case .empty: .zero
        }
    }

    /// Quantité par ingrédient pour cette entrée (liste de courses).
    var shoppingLines: [(ingredient: Ingredient, qty: Double)] {
        switch kind {
        case .recipe(let r): (r.items ?? []).compactMap { it in it.ingredient.map { ($0, qty(for: it) * x) } }
        case .ingredient(let g, let q): [(g, q * x)]
        case .freeMeal, .empty: []
        }
    }

    /// Duplique l'entrée sur un autre jour (et éventuellement un autre repas).
    func copy(to date: DayKey, meal: Meal? = nil, order: Int? = nil) -> PlanEntry? {
        let slot = meal?.rawValue ?? self.slot, order = order ?? self.order
        switch kind {
        case .recipe(let r):
            let e = PlanEntry(date: date, slot: slot, recipe: r, x: x, order: order)
            e.overrides = overrides
            return e
        case .ingredient(let g, let q): return PlanEntry(date: date, slot: slot, ingredient: g, qty: q, x: x, order: order)
        case .freeMeal(let m): return PlanEntry(date: date, slot: slot, free: m, order: order)
        case .empty: return nil
        }
    }
}

/// Repas libre : on estime les kcal (restaurant, repas plaisir) sans recette.
/// Les macros sont facultatives (0 = non précisées). Absent de la liste de courses.
nonisolated struct FreeMeal: Equatable {
    static let defaultName = "Repas libre"
    var name: String
    var kcal: Double
    var p = 0.0, c = 0.0, f = 0.0

    var hasMacros: Bool { p > 0 || c > 0 || f > 0 }
}

@Model
final class AppSettings {
    var targetKcal: Double = 2600
    var targetP: Double = 160
    var targetC: Double = 310
    var targetF: Double = 80
    var shopDays: [Int] = [0, 1, 2, 3, 4, 5, 6]
    /// uid des ingrédients cochés dans la liste de courses.
    var checked: [String] = []
    /// Vue Semaine : du lundi au dimanche plutôt que 7 jours à partir d'aujourd'hui.
    var weekFromMonday = false

    init() {}

    /// Recalcule l'objectif kcal à partir des macros (pour les anciens réglages saisis à la main).
    func syncKcalWithMacros() {
        let k = targets.kcalFromMacros
        if k > 0, k != targetKcal { targetKcal = k }
    }

    var targets: Macros {
        get { Macros(kcal: targetKcal, p: targetP, c: targetC, f: targetF) }
        set {
            targetKcal = newValue.kcal
            targetP = newValue.p
            targetC = newValue.c
            targetF = newValue.f
        }
    }
}

extension Array where Element == PlanEntry {
    func on(_ date: DayKey) -> [PlanEntry] {
        filter { $0.date == date }.sorted { ($0.slot, $0.order) < ($1.slot, $1.order) }
    }
}

extension PlanEntry {
    /// Plats des 7 prochains jours (courses, « À préparer »), avec un jour de marge de chaque côté :
    /// la requête reste juste même si l'écran n'a pas été recréé depuis minuit. Les vues filtrent ensuite
    /// sur les jours choisis.
    static var upcomingDays: Predicate<PlanEntry> {
        let start = Days.adding(-1, to: Days.today), end = Days.adding(8, to: Days.today)
        return #Predicate { $0.date >= start && $0.date < end }
    }
}
