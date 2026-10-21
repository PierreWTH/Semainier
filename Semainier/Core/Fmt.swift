import Foundation

/// Formatage des nombres et quantités, en français.
nonisolated enum Fmt {
    static let fr = Locale(identifier: "fr_FR")

    /// Entier arrondi : « 2 600 ».
    static func n0(_ v: Double) -> String {
        let r = v.rounded()
        return (r == 0 ? 0 : r).formatted(.number.locale(fr).precision(.fractionLength(0)))
    }

    /// Jusqu'à 1 décimale : « 13,5 ».
    static func n1(_ v: Double) -> String {
        v.formatted(.number.locale(fr).precision(.fractionLength(0...1)))
    }

    /// Jusqu'à 2 décimales : « 1,25 ».
    static func n2(_ v: Double) -> String {
        v.formatted(.number.locale(fr).precision(.fractionLength(0...2)))
    }

    /// Multiplicateur de portion : « ×1,0 », « ×1,15 ».
    /// « 1 pièce », « 2 pièces » (plat qui se compte à la pièce).
    static func pieces(_ v: Double) -> String {
        let n = Int(v.rounded())
        return "\(n) pièce\(n > 1 ? "s" : "")"
    }

    static func x(_ v: Double) -> String {
        "×" + v.formatted(.number.locale(fr).precision(.fractionLength(1...2)))
    }

    /// Valeur pour un champ de saisie (pas de séparateur de milliers, vide si 0).
    static func input(_ v: Double) -> String {
        v == 0 ? "" : v.formatted(.number.locale(fr).grouping(.never).precision(.fractionLength(0...2)))
    }

    /// Lit « 12,5 », « 12.5 » ou « 1 200 ». Nil si vide ou invalide.
    static func parse(_ s: String) -> Double? {
        let cleaned = s.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let v = Double(cleaned), v.isFinite else { return nil }
        return v
    }

    /// Écart à l'objectif : « +120 kcal », « −45 kcal », « pile ».
    static func diff(_ kcal: Double, target: Double) -> String {
        let d = (kcal - target).rounded()
        if d == 0 { return "pile" }
        return (d > 0 ? "+" : "−") + n0(abs(d)) + " kcal"
    }

    private static func pieces(_ v: Double, _ text: String) -> String {
        text + (v > 1 ? " pièces" : " pièce")
    }

    /// Affichage en cuisine : grammes arrondis à 5 (au-delà de 25), pièces à 0,5.
    static func cook(_ q: Double, unit: Unit) -> String {
        if unit == .pc {
            let v = (q * 2).rounded() / 2
            return pieces(v, n1(v))
        }
        let v = q < 25 ? q : (q / 5).rounded() * 5
        return n0(v) + " " + unit.short
    }

    /// Liste de courses : arrondi au 5 g/ml supérieur, kg/L dès 1000, pièces à l'unité supérieure.
    static func shop(_ q: Double, unit: Unit) -> String {
        if unit == .pc {
            let v = (q - 0.01).rounded(.up)
            return pieces(v, n0(v))
        }
        // La petite marge évite qu'un 100,0000001 flottant devienne 105.
        let v = (q / 5 - 1e-6).rounded(.up) * 5
        if v >= 1000 { return n2(v / 1000) + (unit == .ml ? " L" : " kg") }
        return n0(v) + " " + unit.short
    }
}
