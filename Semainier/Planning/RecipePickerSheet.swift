import SwiftData
import SwiftUI

/// Choix d'un plat (recette) ou d'un ingrédient seul à placer dans un repas.
/// Toucher ajoute aussitôt ; un appui long passe en sélection multiple (les touchers suivants cochent ou décochent).
/// Un ingrédient demande toujours sa quantité.
struct RecipePickerSheet: View {
    var ref: SlotRef
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]
    @AppStorage(Prefs.addMode) private var mode = AddMode.dishes
    @State private var query = ""
    /// Recherche active dès l'ouverture : le clavier monte avec la fenêtre, on tape le plat directement.
    @State private var searching = true
    @State private var creatingRecipe = false
    @State private var creatingIngredient: IngredientEditTarget?
    @State private var scanning = false
    @State private var quantityFor: Ingredient?
    /// Mode du choix en cours pour un ingrédient : ajout direct ou ajout à la sélection.
    @State private var quantityIsMulti = false
    /// Recette à la pièce dont on demande le nombre.
    @State private var piecesFor: Recipe?
    /// Repas libre en cours de saisie, avec le nom proposé.
    @State private var freeMeal: FreeMealPrompt?
    /// Feuille suivante (nombre de pièces, quantité), ouverte quand l'éditeur de recette ou d'ingrédient a fini de
    /// se fermer : deux feuilles ne s'ouvrent pas en même temps.
    @State private var afterDismiss: (() -> Void)?

    struct FreeMealPrompt: Identifiable {
        let id = UUID()
        var name = ""
    }

    /// Sélection, dans l'ordre où elle a été faite.
    private enum Pick: Equatable {
        /// `x` : nombre de pièces pour une recette qui se compte à la pièce, 1 sinon.
        case recipe(Recipe, x: Double = 1)
        case ingredient(Ingredient, qty: Double)

        var id: PersistentIdentifier {
            switch self {
            case .recipe(let r, _): r.persistentModelID
            case .ingredient(let i, _): i.persistentModelID
            }
        }
    }
    @State private var picks: [Pick] = []

    private func isPicked(_ id: PersistentIdentifier) -> Bool { picks.contains { $0.id == id } }
    private var selecting: Bool { !picks.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        Picker("Type", selection: $mode.animation(.snappy)) {
                            Text("Plats").tag(AddMode.dishes)
                            Text("Ingrédients").tag(AddMode.ingredients)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if selecting {
                                Text("\(picks.count) sélectionné\(picks.count > 1 ? "s" : "")")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                                    .monospacedDigit()
                            }
                            Text(selecting ? "Toucher pour cocher ou décocher." : "Appui long pour en sélectionner plusieurs.")
                        }
                        .padding(.top, 4)
                    }
                    if mode == .ingredients { ingredientRows } else { recipeRows }
                }
                .listRowBackground(Color.surface)
            }
            .screenBackground()
            .searchable(text: $query, isPresented: $searching,
                        prompt: mode == .ingredients ? "Rechercher un ingrédient" : "Rechercher un plat")
            // Recherche active : garde le titre et « Fermer » visibles.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle("Ajouter")
            .navigationSubtitle("\(Days.longLabel(ref.date)) · \(ref.meal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer", role: .close) { dismiss() } }
                // Créer ou scanner un ingrédient : en icônes, pour garder la liste épurée.
                if mode == .ingredients {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Nouvel ingrédient", systemImage: "plus") { creatingIngredient = IngredientEditTarget(draft: IngredientDraft()) }
                        Button("Scanner un produit", systemImage: "barcode.viewfinder") { scanning = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !picks.isEmpty {
                    Button(action: commit) {
                        Text(commitTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .frame(minHeight: 54)
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: picks.count)
            .sensoryFeedback(.selection, trigger: picks.count)
            .sheet(isPresented: $creatingRecipe, onDismiss: runAfterDismiss) {
                RecipeEditor(recipe: nil) { r in
                    let multi = selecting
                    afterDismiss = { choose(r, multi: multi) }
                }
            }
            .sheet(item: $creatingIngredient, onDismiss: runAfterDismiss) { t in
                IngredientEditor(target: t) { i in
                    let multi = selecting
                    afterDismiss = { askQuantity(i, multi: multi) }
                }
            }
            // Le scan ne rend l'ingrédient qu'une fois sa caméra et sa fiche fermées.
            .barcodeScanFlow(isPresented: $scanning, pickExisting: true) { askQuantity($0, multi: selecting) }
            .sheet(item: $freeMeal) { prompt in
                FreeMealSheet(suggestedName: prompt.name) { meal in
                    PlanActions.add(meal, date: ref.date, slot: ref.meal, in: context)
                    // Une sélection en cours reste ouverte ; sinon, comme pour un plat, on referme.
                    if !selecting { dismiss() }
                }
            }
            .sheet(item: $piecesFor) { r in
                PieceCountSheet(recipe: r, confirmTitle: quantityIsMulti ? "Sélectionner" : nil) { n in
                    let pick = Pick.recipe(r, x: Double(n))
                    if quantityIsMulti { picks.append(pick) } else { add([pick]) }
                }
            }
            .sheet(item: $quantityFor) { ing in
                QuantitySheet(ingredient: ing, confirmTitle: quantityIsMulti ? "Sélectionner" : nil) { qty in
                    if quantityIsMulti { picks.append(.ingredient(ing, qty: qty)) } else { add([.ingredient(ing, qty: qty)]) }
                }
            }
        }
        .presentationBackground(Color.appBackground)
    }

    /// « Ajouter 3 ingrédients », « Ajouter 2 plats », ou « Ajouter 4 éléments » si la sélection mélange les deux.
    private var commitTitle: String {
        let n = picks.count, s = n > 1 ? "s" : ""
        let recipes = picks.filter { if case .recipe = $0 { true } else { false } }.count
        let noun = recipes == n ? "plat" : recipes == 0 ? "ingrédient" : "élément"
        return "Ajouter \(n) \(noun)\(s)"
    }

    private func freeMealButton(_ title: String, name: String) -> some View {
        Button { freeMeal = FreeMealPrompt(name: name) } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: FreeMealStyle.icon).foregroundStyle(Color.freeMeal)
            }
        }
    }

    @ViewBuilder
    private func check(_ on: Bool) -> some View {
        if selecting {
            CheckCircle(on: on)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var recipeRows: some View {
        let list = recipes.filtered(query, name: \.name)
        Section {
            ForEach(list) { r in
                let on = isPicked(r.persistentModelID)
                HStack(spacing: 12) {
                    check(on)
                    Text(r.name).foregroundStyle(.primary)
                    Spacer()
                    Text("\(Fmt.n0(r.totals.kcal)) kcal\(r.byPiece ? " / pièce" : "")")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(.rect)
                .listRowBackground(rowBackground(on))
                .onTapGesture { if selecting { toggle(r) } else { choose(r, multi: false) } }
                .onLongPressGesture(minimumDuration: 0.35) { if !on { choose(r, multi: true) } }
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction(named: "Sélectionner plusieurs") { if !on { choose(r, multi: true) } }
            }
        }
        let suggestsFree = list.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty
        // Recherche sans résultat (« pizza ») : on propose d'en faire un repas libre, nom déjà rempli.
        if suggestsFree {
            Section {
                freeMealButton("Ajouter « \(query.trimmingCharacters(in: .whitespaces)) » en repas libre",
                               name: query.trimmingCharacters(in: .whitespaces))
            }
        }
        Section {
            Button("Créer une nouvelle recette", systemImage: "plus") { creatingRecipe = true }
            // Occasionnel : en bas, avec ce qui n'est pas dans les recettes.
            if !suggestsFree { freeMealButton("Repas libre", name: "") }
        } footer: {
            Text("Repas libre : un repas sans recette, dont on estime les kcal.")
        }
    }

    @ViewBuilder
    private var ingredientRows: some View {
        ForEach(Ingredient.byAisle(ingredients, query: query), id: \.aisle) { aisle, items in
            Section {
                ForEach(items) { i in
                    let qty = pickedQty(i)
                    HStack(spacing: 12) {
                        check(qty != nil)
                        IngredientRow(ingredient: i)
                        if let qty {
                            Text(Fmt.cook(qty, unit: i.unit))
                                .font(.subheadline.bold()).foregroundStyle(Color.accentColor).monospacedDigit()
                        }
                    }
                    .contentShape(.rect)
                    .listRowBackground(rowBackground(qty != nil))
                    .onTapGesture { if selecting { toggle(i) } else { askQuantity(i, multi: false) } }
                    .onLongPressGesture(minimumDuration: 0.35) { if qty == nil { askQuantity(i, multi: true) } }
                    .accessibilityAddTraits(qty != nil ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction(named: "Sélectionner plusieurs") { if qty == nil { askQuantity(i, multi: true) } }
                }
            } header: {
                Text(aisle.rawValue).font(.headline).foregroundStyle(.primary).textCase(nil)
            }
        }
    }

    /// Ligne choisie : teintée accent à 8 %.
    private func rowBackground(_ on: Bool) -> some View {
        ZStack {
            Color.surface
            if on { Color.accentColor.opacity(0.08) }
        }
    }

    private func pickedQty(_ i: Ingredient) -> Double? {
        for p in picks { if case .ingredient(let g, let q) = p, g.persistentModelID == i.persistentModelID { return q } }
        return nil
    }

    private func toggle(_ r: Recipe) {
        if isPicked(r.persistentModelID) { picks.removeAll { $0.id == r.persistentModelID } } else { choose(r, multi: true) }
    }

    private func runAfterDismiss() {
        let action = afterDismiss
        afterDismiss = nil
        action?()
    }

    /// Recette à la portion : ajoutée (ou sélectionnée) tout de suite. À la pièce : on demande d'abord le nombre.
    private func choose(_ r: Recipe, multi: Bool) {
        guard r.byPiece else {
            if multi { picks.append(.recipe(r)) } else { add([.recipe(r)]) }
            return
        }
        quantityIsMulti = multi
        piecesFor = r
    }

    private func toggle(_ i: Ingredient) {
        if isPicked(i.persistentModelID) {
            picks.removeAll { $0.id == i.persistentModelID }
        } else {
            askQuantity(i, multi: true)
        }
    }

    private func commit() { add(picks) }

    private func add(_ items: [Pick]) {
        for p in items {
            switch p {
            case .recipe(let r, let x): PlanActions.add(r, x: x, date: ref.date, slot: ref.meal, in: context)
            case .ingredient(let i, let q): PlanActions.add(i, qty: q, date: ref.date, slot: ref.meal, in: context)
            }
        }
        dismiss()
    }

    private func askQuantity(_ i: Ingredient, multi: Bool) {
        quantityIsMulti = multi
        quantityFor = i
    }
}
