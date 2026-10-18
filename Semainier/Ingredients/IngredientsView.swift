import SwiftData
import SwiftUI

struct IngredientsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Query private var ingredients: [Ingredient]
    @State private var editing: IngredientEditTarget?
    @State private var pendingDelete: Ingredient?
    @State private var scanning = false
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Valeurs pour 100 g, 100 ml ou par pièce · produit cru, comme sur l'étiquette")
                        .sectionLabel()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                ForEach(Rayon.allCases) { rayon in
                    let items = filtered.filter { $0.rayon == rayon }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { i in
                                Button { editing = IngredientEditTarget(ingredient: i) } label: { IngredientRow(ingredient: i) }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) { deleteAction(i) }
                                    .listRowBackground(Theme.surface)
                            }
                        } header: {
                            ListHeader(title: rayon.rawValue, trailing: "\(items.count)")
                        }
                    }
                }
            }
            .overlay {
                // En superposition plutôt qu'en ligne de liste : dans une ligne, le bouton Liquid Glass s'étire.
                if ingredients.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun ingrédient", systemImage: "leaf")
                    } description: {
                        Text("Scanne un produit, ou crée un ingrédient à la main. Tu peux aussi en créer depuis une recette.")
                    } actions: {
                        Button("Scanner un produit", systemImage: "barcode.viewfinder") { scanning = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { ing in
                Button("Supprimer (\(Self.usageText(ing)))", role: .destructive) { delete(ing) }
            }
            .paperList()
            .searchable(text: $query, prompt: "Rechercher")
            .navigationTitle("Ingrédients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Nouvel ingrédient", systemImage: "plus") { editing = IngredientEditTarget() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Scanner", systemImage: "barcode.viewfinder") { scanning = true }
                }
            }
            .appChrome()
            .sheet(item: $editing) { IngredientEditor(target: $0) }
            .barcodeScanFlow(isPresented: $scanning)
        }
    }

    /// « retiré de 2 recettes et du planning »
    static func usageText(_ ing: Ingredient) -> String {
        let n = ing.recipeCount
        let parts = [n > 0 ? "de \(n) recette\(n > 1 ? "s" : "")" : nil, ing.planCount > 0 ? "du planning" : nil].compactMap { $0 }
        return "retiré " + parts.joined(separator: " et ")
    }

    private var deleteTitle: String {
        "Supprimer « \(pendingDelete?.name ?? "") » ?"
    }

    /// Suppression directe, sauf si l'ingrédient sert dans des recettes : on demande d'abord.
    /// Le rôle destructif fait disparaître la ligne aussitôt : on ne l'utilise que si la suppression est immédiate,
    /// sinon la ligne s'effacerait puis réapparaîtrait le temps de la confirmation.
    @ViewBuilder
    private func deleteAction(_ ing: Ingredient) -> some View {
        if ing.recipeCount > 0 || ing.planCount > 0 {
            Button("Supprimer", systemImage: "trash") { pendingDelete = ing }
                .tint(Theme.bad)
        } else {
            Button("Supprimer", systemImage: "trash", role: .destructive) { delete(ing) }
        }
    }

    private func delete(_ ing: Ingredient) {
        let name = ing.name
        PlanActions.delete(ing, settings: settings, in: context)
        toast.show("« \(name) » supprimé")
    }

    private var filtered: [Ingredient] {
        ingredients
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct IngredientRow: View {
    var ingredient: Ingredient

    var body: some View {
        let i = ingredient
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(i.name).font(.headline).foregroundStyle(Theme.ink)
                UnitTag(text: i.unit == .pc ? "pièce" : i.unit == .ml ? "100 ml" : "100 g")
                if i.barcode != nil {
                    Image(systemName: "barcode").font(.caption2).foregroundStyle(Theme.muted)
                        .accessibilityLabel("Scanné")
                }
                if i.kcalLooksOff {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warn)
                        .accessibilityLabel("Kcal incohérentes avec les macros")
                }
            }
            Text("\(Text(Fmt.n0(i.kcal)).fontWeight(.semibold).foregroundStyle(Theme.ink)) kcal · \(Text("G").bold().foregroundStyle(Theme.carb)) \(Fmt.n1(i.c)) · \(Text("P").bold().foregroundStyle(Theme.prot)) \(Fmt.n1(i.p)) · \(Text("L").bold().foregroundStyle(Theme.fat)) \(Fmt.n1(i.f))")
                .font(.meta).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// Sélecteur d'ingrédient pour une recette, avec création et scan.
struct IngredientPicker: View {
    var onPick: (Ingredient) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var ingredients: [Ingredient]
    @State private var query = ""
    @State private var creating: IngredientEditTarget?
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Rayon.allCases) { rayon in
                    let items = filtered.filter { $0.rayon == rayon }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { i in
                                Button { pick(i) } label: { IngredientRow(ingredient: i) }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Theme.surface)
                            }
                        } header: {
                            ListHeader(title: rayon.rawValue, trailing: "\(items.count)")
                        }
                    }
                }
            }
            .paperList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un ingrédient")
            .navigationTitle("Choisir un ingrédient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer", role: .close) { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Nouvel ingrédient", systemImage: "plus") { creating = IngredientEditTarget(draft: IngredientDraft()) }
                    Button("Scanner un produit", systemImage: "barcode.viewfinder") { scanning = true }
                }
            }
            .sheet(item: $creating) { t in
                IngredientEditor(target: t) { pick($0) }
            }
            .barcodeScanFlow(isPresented: $scanning, pickExisting: true) { pick($0) }
        }
    }

    private var filtered: [Ingredient] {
        ingredients
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func pick(_ i: Ingredient) {
        onPick(i)
        dismiss()
    }
}
