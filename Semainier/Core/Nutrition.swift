import Foundation

// Logique pure (sans SwiftData ni SwiftUI) : c'est ce que couvrent les tests.

nonisolated enum Unit: String, Codable, CaseIterable, Identifiable {
    case g, ml, pc

    var id: String { rawValue }
    var short: String { rawValue }
    var per: String {
        switch self {
        case .g: "pour 100 g"
        case .ml: "pour 100 ml"
        case .pc: "par pièce"
        }
    }
}

nonisolated enum Rayon: String, Codable, CaseIterable, Identifiable {
    case fruitsLegumes = "Fruits & légumes"
    case viandesPoissons = "Viandes & poissons"
    case cremerieOeufs = "Crèmerie & œufs"
    case boulangerie = "Boulangerie"
    case epicerie = "Épicerie"
    case surgeles = "Surgelés"
    case autre = "Autre"

    var id: String { rawValue }
}

nonisolated enum Week {
    static let days = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    static let short = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    static let slots = ["Petit-déjeuner", "Déjeuner", "Collation", "Dîner"]
    static let slotsShort = ["Petit-déj", "Déjeuner", "Collation", "Dîner"]

    /// Index du jour de la semaine, 0 = lundi.
    static func weekdayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}

nonisolated struct Macros: Equatable {
    var kcal = 0.0, p = 0.0, c = 0.0, f = 0.0

    static let zero = Macros()

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, p: a.p + b.p, c: a.c + b.c, f: a.f + b.f)
    }

    static func * (a: Macros, k: Double) -> Macros {
        Macros(kcal: a.kcal * k, p: a.p * k, c: a.c * k, f: a.f * k)
    }

    /// Kcal déduites des macros (4 / 4 / 9).
    var kcalFromMacros: Double { p * 4 + c * 4 + f * 9 }
}

nonisolated extension Sequence where Element == Macros {
    var sum: Macros { reduce(.zero, +) }
}

nonisolated enum DayStatus {
    case none, ok, warn, bad
}

nonisolated enum Nutrition {
    /// Macros d'une quantité d'ingrédient : valeurs pour 100 g/ml, ou par pièce.
    static func macros(per: Macros, unit: Unit, qty: Double) -> Macros {
        per * (unit == .pc ? qty : qty / 100)
    }

    /// Écart ≤ 3 % = ok, ≤ 8 % = warn, au-delà = bad. Jour vide = none.
    static func status(kcal: Double, target: Double) -> DayStatus {
        guard kcal > 0 else { return .none }
        let r = abs(kcal - target) / max(target, 1)
        return r <= 0.03 ? .ok : r <= 0.08 ? .warn : .bad
    }

    /// Nouveaux multiplicateurs pour qu'un jour tombe sur l'objectif :
    /// x × (objectif / total), arrondi au 0,05, minimum 0,1. Nil si le jour est vide.
    static func fitted(_ xs: [Double], dayKcal: Double, target: Double) -> [Double]? {
        guard dayKcal > 0 else { return nil }
        let k = target / dayKcal
        return xs.map { max(0.1, ($0 * k * 20).rounded() / 20) }
    }

    /// Stepper −/+ : pas de 0,1, minimum 0,1.
    static func stepped(_ x: Double, by delta: Int) -> Double {
        max(0.1, ((x + 0.1 * Double(delta)) * 100).rounded() / 100)
    }

    /// Kcal d'une fiche produit, vérifiées contre les kJ et les macros (4/4/9).
    /// Si les kcal et les kJ ÷ 4,184 se contredisent, on garde la valeur la plus proche des macros
    /// (les kJ si on ne connaît pas les macros). `corrected` indique qu'on a écarté les kcal affichées.
    static func resolveKcal(kcal: Double?, kj: Double?, macroKcal: Double?) -> (value: Double?, corrected: Bool) {
        let fromKJ = kj.map { $0 / 4.184 }
        guard let kcal else { return (fromKJ ?? macroKcal, false) }
        guard let fromKJ, !agree(kcal, fromKJ) else { return (kcal, false) }
        if let m = macroKcal, m > 0, abs(kcal - m) <= abs(fromKJ - m) { return (kcal, false) }
        return (fromKJ, true)
    }

    /// Deux valeurs de kcal concordent à 10 % près (ou 10 kcal pour les petites valeurs).
    private static func agree(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(10, 0.1 * max(a, b))
    }

    /// Kcal d'un ingrédient enregistré qui ne collent pas avec ses macros :
    /// écart de plus de 15 % et de plus de 20 kcal (les fibres et les arrondis restent en dessous).
    static func kcalLooksOff(kcal: Double, macroKcal: Double) -> Bool {
        guard macroKcal > 0 || kcal > 0 else { return false }
        let d = abs(kcal - macroKcal)
        return d > 20 && d > 0.15 * max(kcal, macroKcal)
    }

    /// Dépassement d'un objectif de macro : plus de 3 % au-dessus.
    static let overTolerance = 0.03

    static func isOver(_ value: Double, target: Double) -> Bool {
        target > 0 && value > target * (1 + overTolerance)
    }

    /// Somme des quantités par ingrédient (liste de courses).
    static func aggregate<Key: Hashable>(_ lines: [(key: Key, qty: Double)]) -> [Key: Double] {
        lines.reduce(into: [:]) { $0[$1.key, default: 0] += $1.qty }
    }
}
