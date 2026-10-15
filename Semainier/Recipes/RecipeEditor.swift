import SwiftData
import SwiftUI

struct RecipeEditor: View {
    var recipe: Recipe?
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
    @State private var rows: [Row] = []
    @State private var picking: PickTarget?
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var focusedQty: UUID?
    @FocusState private var nameFocused: Bool

    init(recipe: Recipe?, onSaved: ((Recipe) -> Void)? = nil) {
        self.recipe = recipe
        self.onSaved = onSaved
    }

    private var totals: Macros {
        rows.compactMap { r in r.ingredient.map { $0.macros(qty: Fmt.parse(r.qty) ?? 0) } }.sum
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom du plat") {
                    TextField("Ex. Poulet, riz & brocoli", text: $name)
                        .focused($nameFocused)
                }

                Section {
                    ForEach($rows) { $row in
                        HStack(alignment: .center, spacing: 12) {
                            // Toucher le nom pour choisir un autre ingrédient.
                            Button { picking = PickTarget(id: row.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.ingredient?.name ?? "Choisir un ingrédient")
                                        .foregroundStyle(row.ingredient == nil ? Theme.accent : .primary)
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
                    Text("Ingrédients pour 1 portion")
                } footer: {
                    Text("Glisse vers la gauche pour retirer un ingrédient.")
                }

                Section("Total pour 1 portion") {
                    HStack {
                        Text("\(Text(Fmt.n0(totals.kcal)).font(.title3.bold())) kcal").monospacedDigit()
                        Spacer()
                        MacroLine(m: totals, unit: " g").font(.subheadline)
                    }
                }

                if let error {
                    Text(error).foregroundStyle(Theme.bad).font(.subheadline.weight(.semibold))
                }

                if let recipe {
                    Section {
                        Button("Supprimer la recette", role: .destructive) { confirmDelete = true }
                    } footer: {
                        if recipe.uses > 0 { Text("Elle est utilisée \(recipe.uses)× dans le planning.") }
                    }
                }
            }
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
            .confirmationDialog("Supprimer cette recette ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(recipe.map { $0.uses > 0 ? "Supprimer (retirée \($0.uses)× du planning)" : "Supprimer" } ?? "Supprimer",
                       role: .destructive) {
                    if let recipe { context.delete(recipe) }
                    toast.show("Recette supprimée")
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: load)
    }

    @State private var loaded = false
    @State private var original: (String, [String]) = ("", [])

    private var snapshot: (String, [String]) {
        (name, rows.map { "\($0.ingredient?.uid ?? "")|\($0.qty)" })
    }

    private var isDirty: Bool { loaded && snapshot != original }

    private func load() {
        guard !loaded else { return }
        if let recipe {
            name = recipe.name
            rows = recipe.sortedItems.map { Row(ingredient: $0.ingredient, qty: Fmt.input($0.qty)) }
        } else {
            rows = [Row()]
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
        guard !trimmed.isEmpty else { error = "Donne un nom à la recette."; nameFocused = true; return }
        guard !valid.isEmpty else { error = "Ajoute au moins un ingrédient avec une quantité."; return }

        let r: Recipe
        if let recipe {
            r = recipe
            (r.items ?? []).forEach(context.delete)
        } else {
            r = Recipe(name: trimmed)
            context.insert(r)
        }
        r.name = trimmed
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
                Text(unit == .pc ? "pc" : unit.short).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 92, height: 38)
        .background(Theme.surface2, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Theme.accent : .clear, lineWidth: 1.5))
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture { focus.wrappedValue = id }
        .animation(.snappy, value: focused)
    }
}
