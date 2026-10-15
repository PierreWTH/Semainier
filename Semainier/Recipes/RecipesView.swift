import SwiftData
import SwiftUI

struct RecipeEditTarget: Identifiable {
    let id = UUID()
    var recipe: Recipe?
}

struct RecipesView: View {
    @Query private var recipes: [Recipe]
    @State private var editing: RecipeEditTarget?
    @State private var query = ""

    private var sorted: [Recipe] {
        recipes
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quantités pour une portion. La taille de portion se règle dans le planning.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    if recipes.isEmpty {
                        ContentUnavailableView {
                            Label("Aucune recette", systemImage: "fork.knife")
                        } description: {
                            Text("Ajoute les plats que tu manges en alternance : nom, ingrédients et grammages pour une portion.")
                        } actions: {
                            Button("Créer ma première recette") { editing = RecipeEditTarget() }.buttonStyle(.glassProminent)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                            ForEach(sorted) { r in
                                Button { editing = RecipeEditTarget(recipe: r) } label: { card(r) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .searchable(text: $query, prompt: "Rechercher")
            .navigationTitle("Recettes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Nouvelle recette", systemImage: "plus") { editing = RecipeEditTarget() }
                }
            }
            .appChrome()
            .sheet(item: $editing) { RecipeEditor(recipe: $0.recipe) }
        }
    }

    private func card(_ r: Recipe) -> some View {
        let t = r.totals
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                Spacer()
                Text("\(Fmt.n0(t.kcal)) kcal").font(.system(.body, design: .rounded).bold()).monospacedDigit()
            }
            MacroSplit(m: t)
            HStack {
                MacroLine(m: t, unit: " g")
                Spacer()
                Text(r.upcomingUses > 0 ? "\(r.upcomingUses)× ces 7 jours" : "pas planifiée")
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
        .card(radius: 14, padding: 14)
        .contentShape(.rect)
    }
}
