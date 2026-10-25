import Foundation

/// Plats du planning regroupés par jour, une seule fois par rendu, plutôt que filtrés dans chaque case, chaque puce
/// du bandeau ou chaque total.
///
/// Le regroupement ne lit que la date de chaque plat. Le tri et les totaux sont calculés à la demande, sur la liste
/// (courte) d'un jour, et jamais mis en cache : une portion modifiée est relue par la vue qui l'affiche.
struct PlanIndex {
    /// Tous les plats, dans l'ordre de la requête.
    let all: [PlanEntry]
    private let byDay: [DayKey: [PlanEntry]]

    init(_ entries: [PlanEntry]) {
        all = entries
        byDay = Dictionary(grouping: entries, by: \.date)
    }

    /// Plats du jour, par repas puis dans l'ordre de la case.
    func entries(on day: DayKey) -> [PlanEntry] {
        (byDay[day] ?? []).sorted { ($0.slot, $0.order) < ($1.slot, $1.order) }
    }

    /// Plats valides d'une case, dans l'ordre.
    func entries(on day: DayKey, repas: Repas) -> [PlanEntry] {
        (byDay[day] ?? []).filter { $0.repas == repas && $0.isValid }.sorted { $0.order < $1.order }
    }

    func isEmpty(_ day: DayKey) -> Bool { byDay[day]?.isEmpty ?? true }

    func totals(on day: DayKey) -> Macros { (byDay[day] ?? []).map(\.totals).sum }

    func entry(uid: String) -> PlanEntry? { all.first { $0.uid == uid } }

    /// Moyenne et jours dans la cible sur `days`.
    func stats(_ days: [DayKey], objectif: Double) -> StatsSemaine {
        Nutrition.statsSemaine(days.map { totals(on: $0).kcal }, objectif: objectif)
    }
}
