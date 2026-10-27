import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sauvegarde JSON de toutes les données, au format du brief.
/// À l'import, accepte aussi le format de la maquette HTML (plan en { d0: [{ s, r, x }] }).
nonisolated struct Backup: Codable {
    struct Targets: Codable { var kcal, p, c, f: Double }
    struct Ing: Codable {
        var id: String
        var name: String
        var unit: String
        var kcal, p, c, f: Double
        var aisle: String
        var barcode: String?
        var pieceWeight: Double?
        // Clé « rayon » gardée : les sauvegardes existantes doivent rester lisibles.
        private enum CodingKeys: String, CodingKey {
            case id, name, unit, kcal, p, c, f, aisle = "rayon", barcode, pieceWeight
        }
    }
    struct Item: Codable { var ing: String; var qty: Double }
    struct Rec: Codable {
        var id: String
        var name: String
        var items: [Item]
        /// Se compte à la pièce (absent = à la portion).
        var byPiece: Bool?
        /// Se prépare à l'avance (absent = non).
        var batch: Bool?
    }
    /// `recipe` pour une recette, ou `ing` + `qty` pour un ingrédient seul.
    struct Entry: Codable {
        var id: String
        /// Date du plat (« 2026-10-15 »).
        var date: String?
        /// Anciennes sauvegardes (semaine type, 0 = lundi) : placées sur les 7 prochains jours.
        var day: Int?
        var slot: Int
        var recipe: String?
        var ing: String?
        var qty: Double?
        var x: Double
        /// Quantités modifiées pour ce plat (uid de l'ingrédient → quantité pour 1 portion).
        var overrides: [String: Double]?
        /// Repas libre : nom et valeurs estimées.
        var free: String?
        var kcal, p, c, f: Double?
    }

    var v = 1
    var targets: Targets
    var ingredients: [Ing]
    var recipes: [Rec]
    var plan: [Entry]
    var shopDays: [Int]
    var checked: [String: Bool]

    private struct MockEntry: Codable { var id: String?; var s: Int; var r: String; var x: Double }
    private enum CodingKeys: String, CodingKey { case v, targets, ingredients, recipes, plan, shopDays, checked }

    init(targets: Targets, ingredients: [Ing], recipes: [Rec], plan: [Entry], shopDays: [Int], checked: [String: Bool]) {
        self.targets = targets
        self.ingredients = ingredients
        self.recipes = recipes
        self.plan = plan
        self.shopDays = shopDays
        self.checked = checked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        targets = try c.decodeIfPresent(Targets.self, forKey: .targets) ?? Targets(kcal: 2600, p: 160, c: 310, f: 80)
        ingredients = try c.decodeIfPresent([Ing].self, forKey: .ingredients) ?? []
        recipes = try c.decodeIfPresent([Rec].self, forKey: .recipes) ?? []
        shopDays = try c.decodeIfPresent([Int].self, forKey: .shopDays) ?? Array(0..<7)
        checked = try c.decodeIfPresent([String: Bool].self, forKey: .checked) ?? [:]
        if let entries = try? c.decode([Entry].self, forKey: .plan) {
            plan = entries
        } else if let days = try? c.decode([String: [MockEntry]].self, forKey: .plan) {
            plan = days.flatMap { key, list in
                let day = Int(key.dropFirst()) ?? 0
                return list.map { Entry(id: $0.id ?? UUID().uuidString, day: day, slot: $0.s, recipe: $0.r, x: $0.x) }
            }
        } else {
            plan = []
        }
    }

    @MainActor static func make(from context: ModelContext) -> Backup {
        let s = PlanActions.settings(in: context)
        let ings = context.fetchOrLog(FetchDescriptor<Ingredient>())
        let recs = context.fetchOrLog(FetchDescriptor<Recipe>())
        let entries = context.fetchOrLog(FetchDescriptor<PlanEntry>())
        return Backup(
            targets: Targets(kcal: s.targetKcal, p: s.targetP, c: s.targetC, f: s.targetF),
            ingredients: ings.map { Ing(id: $0.uid, name: $0.name, unit: $0.unitRaw, kcal: $0.kcal, p: $0.p, c: $0.c, f: $0.f, aisle: $0.rayonRaw, barcode: $0.barcode,
                                     pieceWeight: $0.pieceWeight > 0 ? $0.pieceWeight : nil) },
            recipes: recs.map { r in
                Rec(id: r.uid, name: r.name, items: r.sortedItems.compactMap { it in
                    it.ingredient.map { Item(ing: $0.uid, qty: it.qty) }
                }, byPiece: r.byPiece ? true : nil, batch: r.batch ? true : nil)
            },
            plan: entries.compactMap { e in
                switch e.kind {
                case .recipe(let r):
                    Entry(id: e.uid, date: Days.iso(e.date), slot: e.slot, recipe: r.uid, x: e.x,
                          overrides: e.overrides.isEmpty ? nil : e.overrides)
                case .ingredient(let i, let q):
                    Entry(id: e.uid, date: Days.iso(e.date), slot: e.slot, ing: i.uid, qty: q, x: e.x)
                case .freeMeal(let m):
                    Entry(id: e.uid, date: Days.iso(e.date), slot: e.slot, x: 1, free: m.name,
                          kcal: m.kcal, p: m.p, c: m.c, f: m.f)
                case .empty:
                    nil
                }
            },
            shopDays: s.shopDays,
            checked: Dictionary(uniqueKeysWithValues: s.checked.map { ($0, true) })
        )
    }

    /// Remplace toutes les données par celles de la sauvegarde.
    @MainActor func restore(into context: ModelContext, today: DayKey = Days.today) throws {
        // Suppression objet par objet plutôt qu'en lot, pour que les vues ouvertes soient notifiées.
        try context.fetch(FetchDescriptor<PlanEntry>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<RecipeItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Recipe>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Ingredient>()).forEach(context.delete)

        var ings: [String: Ingredient] = [:]
        for i in ingredients {
            let ing = Ingredient(name: i.name, unit: Unit(rawValue: i.unit) ?? .g, kcal: i.kcal, p: i.p, c: i.c, f: i.f,
                                 aisle: Aisle(rawValue: i.aisle) ?? .other, barcode: i.barcode)
            ing.uid = i.id
            ing.pieceWeight = i.pieceWeight ?? 0
            context.insert(ing)
            ings[i.id] = ing
        }
        var recs: [String: Recipe] = [:]
        for r in recipes {
            let rec = Recipe(name: r.name)
            rec.byPiece = r.byPiece ?? false
            rec.batch = r.batch ?? false
            rec.uid = r.id
            context.insert(rec)
            for (n, it) in r.items.enumerated() {
                guard let ing = ings[it.ing] else { continue }
                let item = RecipeItem(ingredient: ing, qty: it.qty, order: n)
                context.insert(item)
                item.recipe = rec
            }
            recs[r.id] = rec
        }
        for (n, e) in plan.enumerated() {
            let date: DayKey
            if let iso = e.date, let k = Days.parseISO(iso) {
                date = k
            } else if let d = e.day, (0..<7).contains(d) {
                date = Days.next(weekday: d, from: today)
            } else {
                continue
            }
            let slot = min(3, max(0, e.slot)), x = e.x > 0 ? e.x : 1
            let entry: PlanEntry
            if let id = e.recipe, let rec = recs[id] {
                entry = PlanEntry(date: date, slot: slot, recipe: rec, x: x, order: n)
                entry.overrides = e.overrides ?? [:]
            } else if let id = e.ing, let ing = ings[id], let qty = e.qty, qty > 0 {
                entry = PlanEntry(date: date, slot: slot, ingredient: ing, qty: qty, x: x, order: n)
            } else if let name = e.free, let kcal = e.kcal, kcal > 0 {
                entry = PlanEntry(date: date, slot: slot,
                                  free: FreeMeal(name: name, kcal: kcal, p: e.p ?? 0, c: e.c ?? 0, f: e.f ?? 0), order: n)
            } else {
                continue
            }
            entry.uid = e.id
            context.insert(entry)
        }

        let s = PlanActions.settings(in: context)
        s.targets = Macros(kcal: targets.kcal > 0 ? targets.kcal : 2600, p: targets.p, c: targets.c, f: targets.f)
        s.syncKcalWithMacros()
        s.shopDays = shopDays.filter { (0..<7).contains($0) }
        s.checked = checked.filter(\.value).map(\.key)
        try context.save()
    }
}

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(_ backup: Backup) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try enc.encode(backup)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
