import Foundation

nonisolated extension Sequence {
    /// Éléments dont le nom contient `query` (tous si elle est vide), triés par nom comme dans le Finder
    /// (accents et chiffres compris : « Œuf » avec les O, « 2 » avant « 10 »).
    func filtered(_ query: String, name: (Element) -> String) -> [Element] {
        filter { query.isEmpty || name($0).localizedStandardContains(query) }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }
}
