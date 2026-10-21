import SwiftData
import SwiftUI

/// Ingrédients seuls d'un repas à enregistrer comme recette (appui long, vues Jour et Semaine).
struct LoneToRecipe: Identifiable {
    let id = UUID()
    var entries: [PlanEntry]

    /// Quantités affichées au planning (portion comprise).
    var prefill: [(ingredient: Ingredient, qty: Double)] {
        entries.compactMap { e in e.ingredient.map { ($0, e.qty * e.x) } }
    }

    var note: String {
        guard let e = entries.first else { return "" }
        return "Les \(entries.count) ingrédients \(e.repas.complement) de \(Days.longLabel(e.date).lowercased()) deviendront un seul plat de cette recette."
    }

    /// « Enregistrer les 4 ingrédients comme recette », pour les menus.
    static func title(_ count: Int) -> String { "Enregistrer les \(count) ingrédients comme recette" }
    static let icon = "square.and.arrow.down.on.square"
}

private struct LoneToRecipeSheet: ViewModifier {
    @Binding var item: LoneToRecipe?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.sheet(item: $item) { group in
            RecipeEditor(recipe: nil, prefill: group.prefill, note: group.note) { recipe in
                withAnimation(.snappy) { PlanActions.replace(group.entries, with: recipe, in: context) }
            }
        }
    }
}

extension View {
    /// Ouvre l'éditeur de recette pré-rempli ; à l'enregistrement, les ingrédients laissent place au plat.
    func saveLoneAsRecipe(_ item: Binding<LoneToRecipe?>) -> some View {
        modifier(LoneToRecipeSheet(item: item))
    }
}
