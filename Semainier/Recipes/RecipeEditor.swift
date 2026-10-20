import SwiftData
import SwiftUI

struct RecipeEditor: View {
    var recipe: Recipe?
    /// Nouvelle recette : ingrédients et quantités de départ (ex. des ingrédients seuls d'un repas).
    var prefill: [(ingredient: Ingredient, qty: Double)] = []
    /// Explication sous le nom (ex. ce que l'enregistrement va changer au planning).
    var note: String?
    var onSaved: ((Recipe) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(Toast.self) private var toast
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let id = UUID()
        var ingredient: Ingredient?
        var qty = ""
    }

    struct PickTarget: Identifiable { let id: UUID }

    @State private var name = ""
    @State private var byPiece = false
    @State private var batch = false
    @State private var rows: [Row] = []
    @State private var picking: PickTarget?
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var focusedQty: UUID?
    @FocusState private var nameFocused: Bool

    init(recipe: Recipe?, prefill: [(ingredient: Ingredient, qty: Double)] = [], note: String? = nil,
         onSaved: ((Recipe) -> Void)? = nil) {
        self.recipe = recipe
        self.prefill = prefill
        self.note = note
        self.onSaved = onSaved
    }

    private var totals: Macros {
        rows.compactMap { r in r.ingredient.map { $0.macros(qty: Fmt.parse(r.qty) ?? 0) } }.sum
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("Ex. Poulet, riz & brocoli", text: $name)
                            .focused($nameFocused)
                    } header: {
                        Text("Nom du plat")
                    } footer: {
                        if let note { Text(note) }
                    }

                    // Interrupteur et non sélecteur segmenté : dans l'appli, le segmenté sert à changer de vue.
                    // Sans note explicative : elle repoussait les ingrédients, l'essentiel de la fiche, vers le bas.
                    Section {
                        Toggle("Se compte à la pièce", isOn: $byPiece.animation(.snappy))
                        Toggle("Se prépare à l'avance", isOn: $batch)
                    }

                    Section {
                        ForEach($rows) { $row in
                            HStack(alignment: .center, spacing: 12) {
                                // Toucher le nom pour choisir un autre ingrédient.
                                Button { picking = PickTarget(id: row.id) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.ingredient?.name ?? "Choisir un ingrédient")
                                            .foregroundStyle(row.ingredient == nil ? Color.accentColor : .primary)
                                            .multilineTextAlignment(.leading)
                                        // Apport de cet ingrédient pour la quantité saisie.
                                        if let g = row.ingredient, let q = Fmt.parse(row.qty), q > 0 {
                                            IngredientMacros(m: g.macros(qty: q))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)

                                QuantityField(text: $row.qty, unit: row.ingredient?.unit, focus: $focusedQty, id: row.id)
                            }
                        }
                        .onDelete { rows.remove(atOffsets: $0) }
                        .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

                        Button("Ajouter un ingrédient", systemImage: "plus") {
                            let r = Row()
                            rows.append(r)
                            picking = PickTarget(id: r.id)
                        }
                    } header: {
                        Text("Ingrédients pour 1 \(byPiece ? "pièce" : "portion")")
                    } footer: {
                        Text("Glisser vers la gauche pour retirer un ingrédient.")
                    }

                    Section("Total pour 1 \(byPiece ? "pièce" : "portion")") {
                        HStack {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(Fmt.n0(totals.kcal)).police(.kcalRecette)
                                Text("kcal").foregroundStyle(Color.texte2)
                            }
                            .monospacedDigit()
                            Spacer()
                            MacroLine(m: totals, unit: " g").font(.subheadline)
                        }
                    }

                    if let error {
                        Text(error).foregroundStyle(Color.depassement).font(.subheadline.weight(.semibold))
                    }

                    if let recipe {
                        Section {
                            Button("Supprimer la recette", role: .destructive) { confirmDelete = true }
                        } footer: {
                            if recipe.uses > 0 { Text("Elle est utilisée \(recipe.uses)× dans le planning.") }
                        }
                    }
                }
                .listRowBackground(Color.surface)
            }
            .fondEcran()
            .navigationTitle(recipe == nil ? "Nouvelle recette" : "Modifier la recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", role: .confirm, action: save) }
            }
            .sheet(item: $picking) { target in
                IngredientPicker { ing in
                    if let i = rows.firstIndex(where: { $0.id == target.id }) {
                        rows[i].ingredient = ing
                        if rows[i].qty.isEmpty {
                            Task {
                                try? await Task.sleep(for: .milliseconds(400))
                                focusedQty = target.id
                            }
                        }
                    }
                }
            }
            .alert("Supprimer cette recette ?", isPresented: $confirmDelete) {
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) {
                    if let recipe { context.delete(recipe) }
                    toast.show("Recette supprimée")
                    dismiss()
                }
            } message: {
                if let recipe, recipe.uses > 0 { Text("Elle sera retirée \(recipe.uses)× du planning.") }
            }
        }
        .presentationBackground(Color.fond)
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: load)
    }

    @State private var loaded = false
    @State private var original: (String, [String]) = ("", [])

    private var snapshot: (String, [String]) {
        ("\(name)|\(byPiece)|\(batch)", rows.map { "\($0.ingredient?.uid ?? "")|\($0.qty)" })
    }

    private var isDirty: Bool { loaded && snapshot != original }

    private func load() {
        guard !loaded else { return }
        if let recipe {
            name = recipe.name
            byPiece = recipe.byPiece
            batch = recipe.batch
            rows = recipe.sortedItems.map { Row(ingredient: $0.ingredient, qty: Fmt.input($0.qty)) }
        } else {
            rows = prefill.isEmpty ? [Row()] : prefill.map { Row(ingredient: $0.ingredient, qty: Fmt.input($0.qty)) }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                nameFocused = true
            }
        }
        original = snapshot
        loaded = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = rows.compactMap { r -> (Ingredient, Double)? in
            guard let g = r.ingredient, let q = Fmt.parse(r.qty), q > 0 else { return nil }
            return (g, q)
        }
        guard !trimmed.isEmpty else { error = "Donner un nom à la recette."; nameFocused = true; return }
        guard !valid.isEmpty else { error = "Ajouter au moins un ingrédient avec une quantité."; return }

        let r: Recipe
        if let recipe {
            r = recipe
            (r.items ?? []).forEach(context.delete)
        } else {
            r = Recipe(name: trimmed)
            context.insert(r)
        }
        r.name = trimmed
        r.byPiece = byPiece
        r.batch = batch
        for (n, (g, q)) in valid.enumerated() {
            let item = RecipeItem(ingredient: g, qty: q, order: n)
            context.insert(item)
            item.recipe = r
        }
        toast.show(recipe == nil ? "Recette créée" : "Recette mise à jour")
        dismiss()
        onSaved?(r)
    }
}

/// Champ de quantité bien visible : pastille de largeur fixe, nombre centré, unité à l'intérieur.
/// Toucher n'importe où sur la pastille ouvre le clavier.
struct QuantityField: View {
    @Binding var text: String
    var unit: Unit?
    var focus: FocusState<UUID?>.Binding
    var id: UUID

    private var focused: Bool { focus.wrappedValue == id }

    var body: some View {
        HStack(spacing: 3) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.semibold)).monospacedDigit()
                .fixedSize()
                .focused(focus, equals: id)
                .accessibilityLabel("Quantité")
            if let unit {
                Text(unit == .pc ? "pc" : unit.short).foregroundStyle(Color.texte2)
            }
        }
        .frame(width: 92, height: 38)
        .background(Color.surface2, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture { focus.wrappedValue = id }
        .animation(.snappy, value: focused)
    }
}
