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
                    Text("Pour 1 portion · portion réglée dans le planning").sectionLabel()
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
        let week = Days.range(from: Days.today, count: 7)
        let used = Set((r.entries ?? []).map(\.date))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.name).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                Spacer()
                Text("\(Text(Fmt.n0(t.kcal)).font(.title3.weight(.bold).width(.expanded)).foregroundStyle(Theme.ink)) \(Text("kcal").font(.caption).foregroundStyle(Theme.muted))")
                    .monospacedDigit()
            }
            MacroSplit(m: t, height: 5)
            HStack {
                MacroLine(m: t, unit: " g").font(.meta).foregroundStyle(Theme.muted)
                Spacer()
                // L'usage sur les 7 prochains jours : un point par jour.
                HStack(spacing: 4) {
                    ForEach(week, id: \.self) { d in
                        Circle().fill(used.contains(d) ? Theme.accent : Theme.surface2).frame(width: 6, height: 6)
                    }
                    Text(r.upcomingUses > 0 ? "\(r.upcomingUses)×" : "—").font(.label).foregroundStyle(Theme.muted)
                        .padding(.leading, 2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(r.upcomingUses > 0 ? "\(r.upcomingUses) fois ces 7 jours" : "Pas planifiée")
            }
        }
        .card(padding: 16)
        .contentShape(.rect)
    }

}
