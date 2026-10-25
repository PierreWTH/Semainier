import Foundation
import SwiftData

/// Un plat à cuisiner pour les jours choisis (onglet Cuisine › « À préparer ») : nombre de portions (ou de pièces),
/// jours où il est prévu, et quantité totale de chaque ingrédient.
struct Preparation: Identifiable {
    var recipe: Recipe
    /// Portions (ou pièces), multiplicateurs compris.
    var total: Double
    /// Nombre de plats par jour.
    var days: [DayKey: Int]
    /// Quantité totale de chaque ingrédient pour toutes ces portions (quantités modifiées d'un plat comprises),
    /// dans l'ordre de la recette.
    var lines: [(ingredient: Ingredient, qty: Double)] = []
    var id: PersistentIdentifier { recipe.persistentModelID }

    /// Plats prévus ces jours-là, préparables à l'avance (`batch`) ou non. Les ingrédients seuls et les repas libres
    /// n'en font pas partie. Sans ordre particulier.
    static func plats(_ entries: [PlanEntry], days: Set<DayKey>, batch: Bool) -> [Preparation] {
        var byRecipe: [PersistentIdentifier: Preparation] = [:]
        for e in entries where days.contains(e.date) {
            guard let r = e.recipe, r.batch == batch else { continue }
            var p = byRecipe[r.persistentModelID] ?? Preparation(recipe: r, total: 0, days: [:])
            p.total += e.x
            p.days[e.date, default: 0] += 1
            if batch {
                for (g, q) in e.shoppingLines {
                    if let i = p.lines.firstIndex(where: { $0.ingredient.persistentModelID == g.persistentModelID }) {
                        p.lines[i].qty += q
                    } else {
                        p.lines.append((g, q))
                    }
                }
            }
            byRecipe[r.persistentModelID] = p
        }
        // Lignes dans l'ordre de la recette (les ingrédients d'un plat ne sont pas rangés en mémoire).
        return byRecipe.values.map { p in
            var p = p
            let order = p.recipe.sortedItems.compactMap { $0.ingredient?.persistentModelID }
            p.lines.sort { (order.firstIndex(of: $0.ingredient.persistentModelID) ?? .max)
                < (order.firstIndex(of: $1.ingredient.persistentModelID) ?? .max) }
            return p
        }
    }

    /// Plats à préparer à l'avance, du plus préparé au moins préparé (puis par nom), filtrés par `query`.
    static func aPreparer(_ entries: [PlanEntry], days: Set<DayKey>, query: String = "") -> [Preparation] {
        plats(entries, days: days, batch: true)
            .filter { query.isEmpty || $0.recipe.name.localizedStandardContains(query) }
            .sorted { plusPrepare($0, $1) }
    }

    private static func plusPrepare(_ a: Preparation, _ b: Preparation) -> Bool {
        if a.total != b.total { return a.total > b.total }
        return a.recipe.name.localizedStandardCompare(b.recipe.name) == .orderedAscending
    }

    /// « tous les jours » (les 7 jours choisis, une fois par jour), ou « lun, mar ×2, jeu » (×2 : deux fois ce
    /// jour-là), dans l'ordre des jours. `chosenCount` : nombre de jours choisis.
    func daysText(chosenCount: Int) -> String {
        if chosenCount == 7 && days.count == 7 && days.values.allSatisfy({ $0 == 1 }) {
            return "tous les jours"
        }
        return days.keys.sorted().map { d in
            let name = Days.shortWeekday(d).lowercased()
            let n = days[d] ?? 1
            return n > 1 ? "\(name) ×\(n)" : name
        }
        .joined(separator: ", ")
    }
}
