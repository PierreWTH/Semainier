import SwiftData
import SwiftUI

/// Côté « Ingrédients » de l'onglet Cuisine : une section par rayon, dans la liste de l'onglet.
struct IngredientRows: View {
    var query: String
    var edit: (IngredientEditTarget) -> Void
    @Query private var ingredients: [Ingredient]

    var body: some View {
        ForEach(Ingredient.parRayon(ingredients, query: query), id: \.rayon) { rayon, items in
            Section(rayon.rawValue) {
                ForEach(items) { i in
                    Button { edit(IngredientEditTarget(ingredient: i)) } label: { IngredientRow(ingredient: i) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// « retiré de 2 recettes et du planning »
    static func usageText(_ ing: Ingredient) -> String {
        let n = ing.recipeCount
        let parts = [n > 0 ? "de \(n) recette\(n > 1 ? "s" : "")" : nil, ing.planCount > 0 ? "du planning" : nil].compactMap { $0 }
        return "retiré " + parts.joined(separator: " et ")
    }
}

struct IngredientRow: View {
    var ingredient: Ingredient

    var body: some View {
        let i = ingredient
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(i.name)
                    if i.barcode != nil {
                        Image(systemName: "barcode").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Scanné")
                    }
                }
                Text("\(i.unit.per) · \(Fmt.n0(i.kcal)) kcal · \(MacroLine.letter(.glucides)) \(Fmt.n1(i.c)) · \(MacroLine.letter(.proteines)) \(Fmt.n1(i.p)) · \(MacroLine.letter(.lipides)) \(Fmt.n1(i.f))")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if i.kcalLooksOff {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: warningSize)).foregroundStyle(Color.attention)
                    .accessibilityLabel("Kcal incohérentes avec les macros")
            }
        }
        .contentShape(.rect)
    }

    @ScaledMetric(relativeTo: .body) private var warningSize: CGFloat = 20
}
