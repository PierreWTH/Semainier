import SwiftData
import SwiftUI

/// Côté « Ingrédients » de l'onglet Cuisine : une section par rayon, dans la liste de l'onglet.
struct IngredientRows: View {
    var query: String
    var edit: (IngredientEditTarget) -> Void
    @Query private var ingredients: [Ingredient]

    var body: some View {
        ForEach(Ingredient.byAisle(ingredients, query: query), id: \.aisle) { aisle, items in
            Section(aisle.rawValue) {
                ForEach(items) { i in
                    Button { edit(IngredientEditTarget(ingredient: i)) } label: { IngredientRow(ingredient: i) }
                        .buttonStyle(.plain)
                }
            }
        }
        FoodLibraryRows(query: query, existingNames: ingredients.map(\.name)) { edit(.library($0)) }
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
                Self.valuesText(i.unit, kcal: i.kcal, c: i.c, p: i.p, f: i.f)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if i.kcalLooksOff {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: warningSize)).foregroundStyle(Color.warning)
                    .accessibilityLabel("Kcal incohérentes avec les macros")
            }
        }
        .contentShape(.rect)
    }

    @ScaledMetric(relativeTo: .body) private var warningSize: CGFloat = 20

    /// « pour 100 g · 350 kcal · G 77,5 · P 7 · L 0,8 », sous le nom.
    static func valuesText(_ unit: Unit, kcal: Double, c: Double, p: Double, f: Double) -> some View {
        Text("\(unit.per) · \(Fmt.n0(kcal)) kcal · \(MacroLine.letter(.carbs)) \(Fmt.n1(c)) · \(MacroLine.letter(.protein)) \(Fmt.n1(p)) · \(MacroLine.letter(.fat)) \(Fmt.n1(f))")
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
    }
}
