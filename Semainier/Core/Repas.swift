import Foundation

/// Les quatre repas d'un jour, dans l'ordre. La valeur brute est celle enregistrée dans `PlanEntry.slot`.
nonisolated enum Repas: Int, CaseIterable, Identifiable, Hashable {
    case petitDejeuner, dejeuner, collation, diner

    var id: Int { rawValue }

    /// « Petit-déjeuner »
    var nom: String {
        switch self {
        case .petitDejeuner: "Petit-déjeuner"
        case .dejeuner: "Déjeuner"
        case .collation: "Collation"
        case .diner: "Dîner"
        }
    }

    /// Nom qui tient dans une colonne de la vue d'ensemble : « P.-déj ».
    var nomCourt: String {
        switch self {
        case .petitDejeuner: "P.-déj"
        case .dejeuner: "Déj"
        case .collation: "Coll"
        case .diner: "Dîner"
        }
    }

    /// « du dîner », « de la collation »
    var complement: String {
        self == .collation ? "de la \(nom.lowercased())" : "du \(nom.lowercased())"
    }

    /// Repas d'une valeur enregistrée ; une valeur hors limites est ramenée au plus proche.
    init(slot: Int) {
        self = Repas(rawValue: min(max(slot, 0), Repas.allCases.count - 1))!
    }
}
