import Foundation

nonisolated extension Sequence {
    /// Éléments dont le nom répond à `query` (tous si elle est vide, voir `Recherche.correspond`), triés par nom
    /// comme dans le Finder (accents et chiffres compris : « Œuf » avec les O, « 2 » avant « 10 »).
    func filtered(_ query: String, name: (Element) -> String) -> [Element] {
        let words = TextSearch.words(query)
        return filter { words.isEmpty || TextSearch.matches(name($0), words) }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }
}

nonisolated enum TextSearch {
    /// Mots d'un texte : lettres et chiffres, ligatures défaites (« Blanc d'œuf » → « Blanc », « d », « oeuf »).
    static func words(_ text: String) -> [Substring] {
        text.withoutLigatures.split { !$0.isLetter && !$0.isNumber }
    }

    /// Chaque mot cherché commence un mot du texte, sans tenir compte de la casse ni des accents :
    /// « oeuf » trouve « Blanc d'œuf » mais pas « Bœuf », « riz » trouve « Farine de riz ».
    static func matches(_ text: String, _ queryWords: [Substring]) -> Bool {
        let present = words(text)
        return queryWords.allSatisfy { m in
            present.contains { $0.range(of: m, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
        }
    }
}

nonisolated extension String {
    /// « Œuf » → « Oeuf » : la recherche du système ignore accents et casse, mais ne rapproche pas une ligature
    /// de ses deux lettres. La table Ciqual écrit « Oeuf », le clavier propose « Œuf ».
    var withoutLigatures: String {
        replacing("œ", with: "oe").replacing("Œ", with: "Oe").replacing("æ", with: "ae").replacing("Æ", with: "Ae")
    }
}
