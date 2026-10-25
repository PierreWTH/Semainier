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

/// Où en est un jour par rapport à l'objectif kcal.
nonisolated enum EtatJour {
    case dansLaCible, auDela, sousObjectif

    var libelle: String {
        switch self {
        case .dansLaCible: "dans la cible"
        case .auDela: "au-delà de l'objectif"
        case .sousObjectif: "sous l'objectif"
        }
    }
}

/// Résumé d'une semaine : moyenne des jours remplis, et jours dans la cible.
nonisolated struct StatsSemaine: Equatable {
    /// Moyenne des kcal des jours qui ont au moins un plat ; 0 si aucun.
    var moyenne: Double
    var dansLaCible: Int
    /// Aucun jour rempli.
    var vide: Bool
}

nonisolated enum Nutrition {
    /// Macros d'une quantité d'ingrédient : valeurs pour 100 g/ml, ou par pièce.
    static func macros(per: Macros, unit: Unit, qty: Double) -> Macros {
        per * (unit == .pc ? qty : qty / 100)
    }

    /// Stepper −/+ de `PortionStepper` : pas de 0,1, minimum 0,1.
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

    /// Au-delà de +3 % de l'objectif, une valeur est en dépassement. Règle unique de l'appli (barres, chiffres, jours).
    static let seuilDepassement = 1.03

    static func depasse(_ valeur: Double, objectif: Double) -> Bool {
        objectif > 0 && valeur / objectif > seuilDepassement
    }

    /// |ratio − 1| ≤ 3 % : dans la cible ; au-delà de +3 % : au-delà ; sinon sous l'objectif (jour vide compris).
    static func etatJour(kcal: Double, objectif: Double) -> EtatJour {
        guard objectif > 0, kcal > 0 else { return .sousObjectif }
        let ratio = kcal / objectif
        if ratio > seuilDepassement { return .auDela }
        return abs(ratio - 1) <= seuilDepassement - 1 ? .dansLaCible : .sousObjectif
    }

    /// Les jours vides ne comptent pas dans la moyenne.
    static func statsSemaine(_ kcal: [Double], objectif: Double) -> StatsSemaine {
        let remplis = kcal.filter { $0 > 0 }
        return StatsSemaine(moyenne: remplis.isEmpty ? 0 : remplis.reduce(0, +) / Double(remplis.count),
                            dansLaCible: kcal.filter { etatJour(kcal: $0, objectif: objectif) == .dansLaCible }.count,
                            vide: remplis.isEmpty)
    }

    /// Somme des quantités par ingrédient (liste de courses).
    static func aggregate<Key: Hashable>(_ lines: [(key: Key, qty: Double)]) -> [Key: Double] {
        lines.reduce(into: [:]) { $0[$1.key, default: 0] += $1.qty }
    }
}
