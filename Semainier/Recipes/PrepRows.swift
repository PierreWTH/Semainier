import SwiftData
import SwiftUI

/// Côté « À préparer » de l'onglet Cuisine : pour les jours cochés (les mêmes que dans Courses), chaque plat prévu
/// qui se prépare à l'avance (`Recipe.batch`) avec le nombre de portions (ou de pièces) à cuisiner, du plus préparé
/// au moins préparé. Les autres plats (shaker, tartine), les ingrédients seuls et les repas libres n'y sont pas.
struct PrepRows: View {
    var query: String
    var edit: (RecipeEditTarget) -> Void
    @Environment(AppSettings.self) private var settings
    @Query(filter: PlanEntry.prochainsJours) private var entries: [PlanEntry]
    /// « portions » à côté du nombre.
    @ScaledMetric(relativeTo: .subheadline) private var unitSize: CGFloat = 14
    /// Chevron comme celui d'un plat de la vue Jour.
    @ScaledMetric(relativeTo: .caption2) private var chevronSize: CGFloat = 10
    /// Plats dépliés (quantités visibles). Repliés par défaut : la liste se lit d'un coup d'œil.
    @State private var unfolded: Set<PersistentIdentifier> = []

    private var chosenDays: Set<DayKey> { Days.chosen(settings.shopDays) }

    var body: some View {
        let days = chosenDays
        let list = Preparation.aPreparer(entries, days: days, query: query)
        // Plats prévus mais non marqués : la liste vide rappelle l'interrupteur.
        let others = list.isEmpty ? Preparation.plats(entries, days: days, batch: false) : []
        if list.isEmpty {
            ContentUnavailableView("Rien à préparer", systemImage: "frying.pan",
                                   description: Text(!query.isEmpty ? "Aucun plat ne correspond."
                                                     : others.isEmpty ? "Aucun plat prévu les jours choisis."
                                                     : "Activer « Se prépare à l'avance » dans la fiche des plats cuisinés en avance."))
                .listRowBackground(Color.clear)
        } else {
            ForEach(list) { p in section(p) }
        }
    }

    /// Un groupe arrondi par plat : « Pâtes Bolo ⌄ ………… 4 portions » (comme les kcal d'une recette), les jours dessous.
    /// Toucher déplie les quantités totales à préparer : des lignes **ajoutées** au groupe, sur `fondDeplie`, que la liste
    /// anime nativement. Agrandir une seule ligne faisait recharger la ligne (la carte disparaissait puis remontait).
    /// La recette s'ouvre par l'appui long.
    @ViewBuilder
    private func section(_ p: Preparation) -> some View {
        let open = unfolded.contains(p.id)
        Section {
            Button {
                withAnimation {
                    if open { unfolded.remove(p.id) } else { unfolded.insert(p.id) }
                }
            } label: {
                header(p, open: open).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.surface)
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 13, trailing: 16))
            // Pas de séparateur système sous l'en-tête (décalé des deux côtés) : la première ligne d'ingrédient
            // trace un filet sur toute la largeur, comme la vue Jour.
            .listRowSeparator(.hidden, edges: .bottom)
            .accessibilityHint(open ? "Masquer les quantités" : "Afficher les quantités")
            .contextMenu {
                Button("Voir la recette", systemImage: "fork.knife") { edit(RecipeEditTarget(recipe: p.recipe)) }
            }
            if open {
                ForEach(Array(p.lines.enumerated()), id: \.offset) { i, l in
                    line(l.ingredient, l.qty)
                        .padding(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                        // Filet dans le fond de la ligne, qui commence exactement où finit l'en-tête (le contenu,
                        // centré dans la ligne, le plaçait quelques points plus bas).
                        .listRowBackground(Color.fondDeplie.overlay(alignment: .top) {
                            if i == 0 { Color.filetCarte.frame(height: 1) }
                        })
                        .listRowInsets(EdgeInsets())
                        // Entre deux ingrédients : séparateur décalé de 16 à gauche.
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
                }
            }
        }
        .listRowSeparatorTint(Color.filetCarte)
        .listSectionSpacing(10)
    }

    private func header(_ p: Preparation, open: Bool) -> some View {
        let byPiece = p.recipe.byPiece
        let unit = byPiece ? (p.total > 1 ? "pièces" : "pièce") : (p.total > 1 ? "portions" : "portion")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(p.recipe.name).font(.headline).multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: chevronSize, weight: .bold))
                        .foregroundStyle(Color.texte3)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(byPiece ? Fmt.n0(p.total) : Fmt.n1(p.total)).police(.kcalRecette)
                    Text(unit).font(.system(size: unitSize)).foregroundStyle(Color.texte2)
                }
                .monospacedDigit()
                .fixedSize()
            }
            Text(p.daysText(chosenCount: chosenDays.count)).font(.footnote).foregroundStyle(Color.texte2)
        }
    }

    /// « Penne rigate ………… 280 g » : nom 16, quantité Rounded Semibold, unité Regular `texte2`.
    private func line(_ g: Ingredient, _ qty: Double) -> some View {
        let q = QuantityParts(Fmt.cook(qty, unit: g.unit))
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(g.name).font(.callout).foregroundStyle(Color.texte)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(q.number).police(.quantite).foregroundStyle(Color.texte)
                if let unit = q.unit {
                    Text(unit).font(.callout).foregroundStyle(Color.texte2)
                }
            }
            .monospacedDigit()
            .fixedSize()
        }
    }
}
