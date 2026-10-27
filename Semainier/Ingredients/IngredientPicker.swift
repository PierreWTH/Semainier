import SwiftData
import SwiftUI

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
                Group {
                    ForEach(Ingredient.byAisle(ingredients, query: query), id: \.aisle) { aisle, items in
                        Section(aisle.rawValue) {
                            ForEach(items) { i in
                                Button { pick(i) } label: { IngredientRow(ingredient: i) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    FoodLibraryRows(query: query, existingNames: ingredients.map(\.name)) { creating = .library($0) }
                }
                .listRowBackground(Color.surface)
            }
            .screenBackground()
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
        .presentationBackground(Color.appBackground)
    }

    private func pick(_ i: Ingredient) {
        onPick(i)
        dismiss()
    }
}
