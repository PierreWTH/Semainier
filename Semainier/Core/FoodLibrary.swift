import Foundation

/// Aliment brut de la bibliothèque (table Ciqual de l'Anses), valeurs pour 100 g d'aliment cru.
nonisolated struct RawFood: Decodable, Identifiable, Hashable {
    /// Code Ciqual.
    let code: Int
    let name: String
    /// Autres noms trouvés par la recherche (« basmati » pour le riz blanc, « olive » pour l'huile).
    let aliases: String
    let aisle: Aisle
    let kcal: Double
    let p: Double
    let c: Double
    let f: Double

    var id: Int { code }
}

/// Bibliothèque d'aliments bruts, générée par `scripts/ciqual.py` dans `Ressources/ciqual.json`.
nonisolated enum FoodLibrary {
    /// Mention exigée par la licence CC-BY 4.0 de la table Ciqual.
    static let source = "Anses, Ciqual 2025"

    static let foods: [RawFood] = load(Bundle.main.url(forResource: "ciqual", withExtension: "json"))

    private struct LibraryFile: Decodable {
        let foods: [RawFood]
    }

    static func load(_ url: URL?) -> [RawFood] {
        guard let url else {
            Journal.store.error("Bibliothèque Ciqual absente de l'appli")
            return []
        }
        do {
            return try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: url)).foods
        } catch {
            Journal.store.error("Bibliothèque Ciqual illisible : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Aliments dont le nom ou les autres noms répondent à `query` (aucun si elle est vide, voir
    /// `Recherche.correspond`), sauf ceux déjà enregistrés sous le même nom. Ceux dont le nom commence par la
    /// recherche passent devant.
    static func search(_ query: String, excluding existingNames: [String] = [], from list: [RawFood] = foods)
        -> [RawFood] {
        let q = query.trimmingCharacters(in: .whitespaces).withoutLigatures
        let words = TextSearch.words(q)
        guard !words.isEmpty else { return [] }
        let existingKeys = Set(existingNames.map(normalizedKey))
        let found = list.filter { a in
            TextSearch.matches(a.name + " " + a.aliases, words) && !existingKeys.contains(normalizedKey(a.name))
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
        return found.sorted { a, b in
            let da = a.name.withoutLigatures.range(of: q, options: options) != nil
            let db = b.name.withoutLigatures.range(of: q, options: options) != nil
            if da != db { return da }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Nom comparable : sans casse, accents ni ligatures, espaces de bord retirés.
    private static func normalizedKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).withoutLigatures
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
