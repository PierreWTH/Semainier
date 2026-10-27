import SwiftUI

/// Aliments bruts de la bibliothèque Ciqual qui répondent à la recherche, sous les ingrédients enregistrés.
/// Rien tant que la recherche est vide. Toucher un aliment ouvre sa fiche préremplie, pour l'ajouter aux ingrédients.
struct FoodLibraryRows: View {
    var query: String
    /// Noms des ingrédients déjà enregistrés : un aliment ajouté ne revient pas dans la bibliothèque.
    var existingNames: [String]
    /// Titre de section en 17 Semibold, comme les rayons de la feuille « Ajouter ».
    var boldHeader = false
    var onChoose: (RawFood) -> Void

    /// Au-delà, la liste devient trop longue à parcourir : mieux vaut préciser la recherche.
    private static let maxResults = 25

    var body: some View {
        let found = FoodLibrary.search(query, excluding: existingNames)
        if !found.isEmpty {
            Section {
                ForEach(found.prefix(Self.maxResults)) { a in
                    Button { onChoose(a) } label: { FoodLibraryRow(food: a) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ouvre sa fiche pour l'ajouter aux ingrédients")
                }
            } header: {
                if boldHeader {
                    Text("Aliments bruts").font(.headline).foregroundStyle(.primary).textCase(nil)
                } else {
                    Text("Aliments bruts")
                }
            } footer: {
                let remaining = found.count - Self.maxResults
                Text((remaining > 0 ? "Encore \(remaining) aliments : préciser la recherche. " : "")
                     + "Valeurs \(FoodLibrary.source), pour 100 g d'aliment cru.")
            }
        }
    }
}

struct FoodLibraryRow: View {
    var food: RawFood

    var body: some View {
        let a = food
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name)
                IngredientRow.valuesText(.g, kcal: a.kcal, c: a.c, p: a.p, f: a.f)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "plus.circle")
                .font(.system(size: iconSize)).foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
}

extension IngredientEditTarget {
    /// Fiche d'un nouvel ingrédient, préremplie avec un aliment de la bibliothèque.
    static func library(_ a: RawFood) -> IngredientEditTarget {
        IngredientEditTarget(draft: IngredientDraft(food: a),
                             note: "Valeurs \(FoodLibrary.source), pour 100 g d'aliment cru. Pour le compter à la pièce, choisir « Par pièce » et indiquer son poids.",
                             noteIcon: "leaf")
    }
}
