import SwiftData
import SwiftUI

struct RecipeEditTarget: Identifiable {
    let id = UUID()
    var recipe: Recipe?
}

/// Côté « Plats » de l'onglet Cuisine : les recettes en cartes, comme lignes de la liste de l'onglet
/// (une seule liste pour les deux côtés, pour que le grand titre ne se recharge pas à la bascule).
struct RecipeRows: View {
    var query: String
    var edit: (RecipeEditTarget) -> Void
    @Query private var recipes: [Recipe]
    /// « kcal » à côté des kcal d'une recette.
    @ScaledMetric(relativeTo: .subheadline) private var unitSize: CGFloat = 14

    var body: some View {
        ForEach(recipes.filtres(query, nom: \.name)) { r in
            Button { edit(RecipeEditTarget(recipe: r)) } label: { card(r) }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
    }

    private func card(_ r: Recipe) -> some View {
        let t = r.totals
        let shape = RoundedRectangle(cornerRadius: Arrondi.carteRecette)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.name).font(.headline).multilineTextAlignment(.leading)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.n0(t.kcal)).police(.kcalRecette)
                    Text(r.byPiece ? "kcal / pièce" : "kcal").font(.system(size: unitSize)).foregroundStyle(Color.texte2)
                }
                .monospacedDigit()
            }
            BarreRepartition(g: t.c, p: t.p, l: t.f, hauteur: 4)
            HStack {
                MacroLine(m: t, unit: " g").foregroundStyle(Color.texte2)
                Spacer()
                Text(r.upcomingUses > 0 ? "\(r.upcomingUses)× ces 7 jours" : "pas planifiée").foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 13, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: shape)
        .contentShape(.rect)
    }
}
