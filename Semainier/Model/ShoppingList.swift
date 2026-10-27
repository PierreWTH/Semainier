import Foundation
import SwiftData

/// Liste de courses : quantité totale de chaque ingrédient sur les jours choisis, portions ajustées et quantités
/// modifiées d'un plat comprises. Les repas libres n'y figurent pas.
struct ShoppingList {
    struct Line: Identifiable {
        var ingredient: Ingredient
        var qty: Double
        var id: PersistentIdentifier { ingredient.persistentModelID }
        /// « 250 g », « 1,2 kg », « 3 pièces »
        var text: String { Fmt.shop(qty, unit: ingredient.unit) }
    }

    /// Une ligne par ingrédient, sans ordre particulier.
    let lines: [Line]

    init(entries: [PlanEntry], days: Set<DayKey>) {
        var byID: [PersistentIdentifier: Ingredient] = [:]
        var raw: [(key: PersistentIdentifier, qty: Double)] = []
        for e in entries where days.contains(e.date) {
            for (g, q) in e.shoppingLines {
                byID[g.persistentModelID] = g
                raw.append((g.persistentModelID, q))
            }
        }
        lines = Nutrition.aggregate(raw).compactMap { id, q in
            guard q > 0, let g = byID[id] else { return nil }
            return Line(ingredient: g, qty: q)
        }
    }

    var isEmpty: Bool { lines.isEmpty }

    /// Rayons non vides, dans l'ordre du magasin. Dans chacun : ce qui reste à acheter d'abord, puis par nom.
    /// `coches` : uid des ingrédients déjà dans le panier.
    func byAisle(checkedKeys: Set<String>) -> [(aisle: Aisle, lines: [Line])] {
        Aisle.allCases.compactMap { aisle in
            let items = lines.filter { $0.ingredient.aisle == aisle }.sorted {
                let a = checkedKeys.contains($0.ingredient.uid), b = checkedKeys.contains($1.ingredient.uid)
                if a != b { return !a }
                return $0.ingredient.name.localizedStandardCompare($1.ingredient.name) == .orderedAscending
            }
            return items.isEmpty ? nil : (aisle, items)
        }
    }

    /// Texte à copier ou partager : ce qui reste à acheter, par rayon.
    /// « Liste de courses (7 prochains jours) », puis « Épicerie », « - Riz : 500 g »…
    func text(checkedKeys: Set<String>, days: String) -> String {
        var out = "Liste de courses (\(days))\n"
        for (aisle, items) in byAisle(checkedKeys: checkedKeys) {
            let todo = items.filter { !checkedKeys.contains($0.ingredient.uid) }
            guard !todo.isEmpty else { continue }
            out += "\n\(aisle.rawValue)\n" + todo.map { "- \($0.ingredient.name) : \($0.text)" }.joined(separator: "\n") + "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// « 7 prochains jours », ou « Lun 26, Mar 27 » (décalages depuis aujourd'hui).
    static func daysText(_ shopDays: [Int], today: DayKey = Days.today) -> String {
        shopDays.count == 7 ? "7 prochains jours"
            : shopDays.sorted().map { Days.shortLabel(Days.adding($0, to: today)) }.joined(separator: ", ")
    }
}
