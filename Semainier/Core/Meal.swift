import Foundation

/// Les quatre repas d'un jour, dans l'ordre. La valeur brute est celle enregistrée dans `PlanEntry.slot`.
nonisolated enum Meal: Int, CaseIterable, Identifiable, Hashable {
    case breakfast, lunch, snack, dinner

    var id: Int { rawValue }

    /// « Petit-déjeuner »
    var name: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .snack: "Collation"
        case .dinner: "Dîner"
        }
    }

    /// Nom qui tient dans une colonne de la vue d'ensemble : « P.-déj ».
    var shortName: String {
        switch self {
        case .breakfast: "P.-déj"
        case .lunch: "Déj"
        case .snack: "Coll"
        case .dinner: "Dîner"
        }
    }

    /// « du dîner », « de la collation »
    var complement: String {
        self == .snack ? "de la \(name.lowercased())" : "du \(name.lowercased())"
    }

    /// Repas d'une valeur enregistrée ; une valeur hors limites est ramenée au plus proche.
    init(slot: Int) {
        self = Meal(rawValue: min(max(slot, 0), Meal.allCases.count - 1))!
    }
}
