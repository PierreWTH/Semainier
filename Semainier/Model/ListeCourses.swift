import Foundation
import SwiftData

/// Liste de courses : quantité totale de chaque ingrédient sur les jours choisis, portions ajustées et quantités
/// modifiées d'un plat comprises. Les repas libres n'y figurent pas.
struct ListeCourses {
    struct Ligne: Identifiable {
        var ingredient: Ingredient
        var qty: Double
        var id: PersistentIdentifier { ingredient.persistentModelID }
        /// « 250 g », « 1,2 kg », « 3 pièces »
        var text: String { Fmt.shop(qty, unit: ingredient.unit) }
    }

    /// Une ligne par ingrédient, sans ordre particulier.
    let lignes: [Ligne]

    init(entries: [PlanEntry], days: Set<DayKey>) {
        var byID: [PersistentIdentifier: Ingredient] = [:]
        var raw: [(key: PersistentIdentifier, qty: Double)] = []
        for e in entries where days.contains(e.date) {
            for (g, q) in e.shoppingLines {
                byID[g.persistentModelID] = g
                raw.append((g.persistentModelID, q))
            }
        }
        lignes = Nutrition.aggregate(raw).compactMap { id, q in
            guard q > 0, let g = byID[id] else { return nil }
            return Ligne(ingredient: g, qty: q)
        }
    }

    var isEmpty: Bool { lignes.isEmpty }

    /// Rayons non vides, dans l'ordre du magasin. Dans chacun : ce qui reste à acheter d'abord, puis par nom.
    /// `coches` : uid des ingrédients déjà dans le panier.
    func parRayon(coches: Set<String>) -> [(rayon: Rayon, lignes: [Ligne])] {
        Rayon.allCases.compactMap { rayon in
            let items = lignes.filter { $0.ingredient.rayon == rayon }.sorted {
                let a = coches.contains($0.ingredient.uid), b = coches.contains($1.ingredient.uid)
                if a != b { return !a }
                return $0.ingredient.name.localizedStandardCompare($1.ingredient.name) == .orderedAscending
            }
            return items.isEmpty ? nil : (rayon, items)
        }
    }

    /// Texte à copier ou partager : ce qui reste à acheter, par rayon.
    /// « Liste de courses (7 prochains jours) », puis « Épicerie », « - Riz : 500 g »…
    func texte(coches: Set<String>, jours: String) -> String {
        var out = "Liste de courses (\(jours))\n"
        for (rayon, items) in parRayon(coches: coches) {
            let todo = items.filter { !coches.contains($0.ingredient.uid) }
            guard !todo.isEmpty else { continue }
            out += "\n\(rayon.rawValue)\n" + todo.map { "- \($0.ingredient.name) : \($0.text)" }.joined(separator: "\n") + "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// « 7 prochains jours », ou « Lun 26, Mar 27 » (décalages depuis aujourd'hui).
    static func joursTexte(_ shopDays: [Int], today: DayKey = Days.today) -> String {
        shopDays.count == 7 ? "7 prochains jours"
            : shopDays.sorted().map { Days.shortLabel(Days.adding($0, to: today)) }.joined(separator: ", ")
    }
}
