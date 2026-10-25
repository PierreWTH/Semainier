import Foundation

nonisolated extension Sequence {
    /// Éléments dont le nom contient `query` (tous si elle est vide), triés par nom comme dans le Finder
    /// (accents et chiffres compris : « Œuf » avec les O, « 2 » avant « 10 »).
    func filtres(_ query: String, nom: (Element) -> String) -> [Element] {
        filter { query.isEmpty || nom($0).localizedStandardContains(query) }
            .sorted { nom($0).localizedStandardCompare(nom($1)) == .orderedAscending }
    }
}
