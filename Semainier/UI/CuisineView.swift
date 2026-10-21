import SwiftData
import SwiftUI

/// Onglet Cuisine : les plats (recettes), les ingrédients, et « À préparer » (portions à cuisiner pour les jours
/// choisis, pour le batch cooking). Une seule liste pour les trois côtés : à la bascule, seul son contenu change,
/// le grand titre reste en place.
struct CuisineView: View {
    @AppStorage(Prefs.modeCuisine) private var mode = ModeCuisine.plats
    @Query private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]
    @State private var query = ""
    @State private var editingRecipe: RecipeEditTarget?
    @State private var editingIngredient: IngredientEditTarget?
    @State private var scanning = false

    private var showsIngredients: Bool { mode == .ingredients }
    private var showsPrep: Bool { mode == .preparer }

    var body: some View {
        NavigationStack {
            // Une seule liste pour les trois côtés : à la bascule, seul son contenu change, le grand titre et le
            // sélecteur restent en place (un conteneur à part pour un côté faisait sauter le contenu, recherche active).
            list
            // En superposition plutôt qu'en ligne de liste : dans une ligne, le bouton Liquid Glass s'étire.
            .overlay { emptyState }
            .searchable(text: $query, prompt: showsIngredients ? "Rechercher un ingrédient" : "Rechercher un plat")
            .navigationTitle("Cuisine")
            .toolbar {
                // Côté Ingrédients, « + » et « scan » partagent une même capsule en verre.
                // Rien à créer côté « À préparer » : on y lit ce qui est prévu.
                ToolbarItemGroup(placement: .topBarLeading) {
                    if showsIngredients {
                        Button("Nouvel ingrédient", systemImage: "plus") { editingIngredient = IngredientEditTarget() }
                        Button("Scanner", systemImage: "barcode.viewfinder") { scanning = true }
                    } else if !showsPrep {
                        Button("Nouvelle recette", systemImage: "plus") { editingRecipe = RecipeEditTarget() }
                    }
                }
            }
            .appChrome()
            .sheet(item: $editingRecipe) { RecipeEditor(recipe: $0.recipe) }
            .sheet(item: $editingIngredient) { IngredientEditor(target: $0) }
            .barcodeScanFlow(isPresented: $scanning)
        }
    }

    /// Plats, Ingrédients, À préparer : liste groupée.
    private var list: some View {
            List {
                Section {
                    CuisinePicker(mode: $mode)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    if !showsPrep {
                        Text(showsIngredients
                             ? "Valeurs pour 100 g, 100 ml ou par pièce (produit cru, comme sur l'étiquette)."
                             : "Quantités pour une portion (ou une pièce). Le nombre se règle dans le planning.")
                            .padding(.top, 4)
                    }
                }
                if showsPrep {
                    Section {
                    } header: {
                        ShopDayPicker()
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Portions à cuisiner pour les jours choisis (les mêmes que dans Courses), portions ajustées comprises.")
                    }
                    PrepRows(query: query, edit: { editingRecipe = $0 })
                } else if showsIngredients {
                    IngredientRows(query: query, edit: { editingIngredient = $0 })
                        .listRowBackground(Color.surface)
                } else {
                    Section {
                        RecipeRows(query: query, edit: { editingRecipe = $0 })
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fondEcran()
    }

    @ViewBuilder
    private var emptyState: some View {
        if showsIngredients && ingredients.isEmpty {
            ContentUnavailableView {
                Label("Aucun ingrédient", systemImage: "leaf")
            } description: {
                Text("Scanner un produit, ou créer un ingrédient à la main. On peut aussi en créer depuis une recette.")
            } actions: {
                Button("Scanner un produit", systemImage: "barcode.viewfinder") { scanning = true }
                    .buttonStyle(.glassProminent)
            }
        } else if !showsIngredients && !showsPrep && recipes.isEmpty {
            ContentUnavailableView {
                Label("Aucune recette", systemImage: "fork.knife")
            } description: {
                Text("Ajouter les plats mangés en alternance : nom, ingrédients et grammages pour une portion.")
            } actions: {
                Button("Créer ma première recette") { editingRecipe = RecipeEditTarget() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// « Plats | Ingrédients | À préparer » : change de vue.
struct CuisinePicker: View {
    @Binding var mode: ModeCuisine

    var body: some View {
        Picker("Afficher", selection: $mode.animation(.snappy)) {
            Text("Plats").tag(ModeCuisine.plats)
            Text("Ingrédients").tag(ModeCuisine.ingredients)
            Text("À préparer").tag(ModeCuisine.preparer)
        }
        .pickerStyle(.segmented)
    }
}
