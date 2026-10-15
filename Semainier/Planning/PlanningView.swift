import SwiftData
import SwiftUI

struct SlotRef: Identifiable, Hashable {
    var date: DayKey
    var slot: Int
    var id: Int { date * 10 + slot }
}

struct PlanningView: View {
    @Environment(\.modelContext) private var context
    @Environment(Toast.self) private var toast
    @Query private var entries: [PlanEntry]
    @Query private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]
    // État local (animable) ; recopié dans les préférences pour s'en souvenir au prochain lancement.
    // Une écriture directe dans @AppStorage n'est pas animée.
    @State private var mode = UserDefaults.standard.string(forKey: "planning.mode") ?? "semaine"
    /// Jour sélectionné (vue jour, pastille de la semaine).
    @State private var day = Days.today
    /// Fenêtre de jours affichée : 7 jours à partir d'aujourd'hui, agrandie par paquets de 7.
    @State private var windowStart = Days.today
    @State private var windowCount = 7
    @State private var adding: SlotRef?
    @State private var newRecipe = false
    @State private var copying = false
    @State private var confirmClear = false
    /// Relie la colonne touchée dans la semaine à la pastille du jour (animation de bascule).
    @Namespace private var dayNS

    private var windowDays: [DayKey] { Days.range(from: windowStart, count: windowCount) }

    /// Les 7 jours de la bande de la vue jour : le paquet de la fenêtre qui contient le jour choisi.
    private var stripDays: [DayKey] {
        let block = max(0, Days.distance(from: windowStart, to: day)) / 7
        return Days.range(from: Days.adding(block * 7, to: windowStart), count: 7)
    }

    private func extend(backward: Bool) {
        withAnimation(.snappy) {
            if backward { windowStart = Days.adding(-7, to: windowStart) }
            windowCount += 7
        }
    }

    /// Bouton « Aujourd'hui » : revient sur aujourd'hui et referme les jours passés (jusqu'au prochain tiré).
    private var awayFromToday: Bool { windowStart != Days.today || windowCount != 7 || day != Days.today }

    private func backToToday() {
        withAnimation(.modeSwitch) {
            day = Days.today
            windowStart = Days.today
            windowCount = 7
        }
    }

    /// Garde le jour choisi dans la fenêtre (navigation au-delà en vue jour).
    private func keepDayInWindow() {
        while day < windowStart { windowStart = Days.adding(-7, to: windowStart); windowCount += 7 }
        while Days.distance(from: windowStart, to: day) >= windowCount { windowCount += 7 }
    }

    /// Rien à planifier tant qu'il n'y a ni recette ni ingrédient.
    private var isEmpty: Bool { recipes.isEmpty && ingredients.isEmpty && entries.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            ContentUnavailableView {
                                Label("Ton planning t'attend", systemImage: "calendar")
                            } description: {
                                Text("Crée d'abord tes recettes ou tes ingrédients. Tu pourras ensuite les placer sur chaque jour.")
                            } actions: {
                                Button("Créer une recette") { newRecipe = true }.buttonStyle(.glassProminent)
                            }
                        }
                        .padding()
                    }
                } else {
                    // Un seul défilement pour les deux vues : la bascule s'anime et le grand titre reste en place.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ModePicker(mode: $mode)
                            if mode == "jour" {
                                DayView(day: $day, stripDays: stripDays, entries: entries, ns: dayNS,
                                        add: { adding = SlotRef(date: day, slot: $0) })
                                    .transition(.modeSwitch(.offset(y: 28)))
                            } else {
                                WeekView(entries: entries, days: windowDays, selected: day, ns: dayNS,
                                         openDay: { d in day = d; withAnimation(.modeSwitch) { mode = "jour" } },
                                         add: { adding = SlotRef(date: $0, slot: $1) },
                                         extend: extend(backward:))
                                    .transition(.modeSwitch(.scale(scale: 0.97, anchor: .top)))
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Theme.bg)
            .onChange(of: mode) { UserDefaults.standard.set(mode, forKey: "planning.mode") }
            .onChange(of: day) { keepDayInWindow() }
            .navigationTitle(isEmpty ? "Planning" : mode == "jour" ? Days.weekday(day) : "Semaine")
            .navigationSubtitle(isEmpty ? "" : mode == "jour" ? daySubtitle
                                : Days.rangeText(windowStart, Days.adding(windowCount - 1, to: windowStart)))
            .toolbar {
                if !isEmpty && awayFromToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Aujourd'hui", action: backToToday)
                    }
                }
            }
            .appChrome(showTargets: true) {
                if mode == "jour" && !isEmpty {
                    Button("Copier ce jour vers…", systemImage: "doc.on.doc") { copying = true }
                        .disabled(entries.on(day).isEmpty)
                    Button("Vider ce jour", systemImage: "trash", role: .destructive) { confirmClear = true }
                        .disabled(entries.on(day).isEmpty)
                }
            }
            .confirmationDialog("Tout retirer du \(Days.longLabel(day).lowercased()) ?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Vider ce jour", role: .destructive) {
                    withAnimation { entries.on(day).forEach(context.delete) }
                    toast.show("\(Days.longLabel(day)) vidé")
                }
            }
            .sheet(isPresented: $copying) { CopyDaySheet(source: day, entries: entries) }
            .sheet(item: $adding) { ref in RecipePickerSheet(ref: ref) }
            .sheet(isPresented: $newRecipe) { RecipeEditor(recipe: nil) }
        }
    }

    /// « aujourd'hui · 15 octobre », ou « 15 octobre ».
    private var daySubtitle: String {
        [Days.relative(day), Days.dayMonth(day)].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Animation {
    /// Bascule Semaine ↔ Jour : ressort léger.
    static let modeSwitch = Animation.spring(duration: 0.5, bounce: 0.22)
}

extension AnyTransition {
    /// L'écran entrant arrive en fondu avec `motion` ; le sortant s'efface très vite pour éviter la double image.
    static func modeSwitch(_ motion: AnyTransition) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: motion),
                    removal: .opacity.animation(.easeOut(duration: 0.12)))
    }
}

/// Bascule Semaine / Jour, en tête des deux vues.
struct ModePicker: View {
    @Binding var mode: String

    var body: some View {
        Picker("Vue", selection: $mode.animation(.modeSwitch)) {
            Text("Semaine").tag("semaine")
            Text("Jour").tag("jour")
        }
        .pickerStyle(.segmented)
    }
}

/// Choix d'un plat (recette) ou d'un ingrédient seul à placer dans un repas.
/// Toucher ajoute aussitôt ; un appui long passe en sélection multiple (les touchers suivants cochent ou décochent).
/// Un ingrédient demande toujours sa quantité.
struct RecipePickerSheet: View {
    var ref: SlotRef
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]
    @AppStorage("picker.mode") private var mode = "plats"
    @State private var query = ""
    @State private var creatingRecipe = false
    @State private var creatingIngredient: IngredientEditTarget?
    @State private var scanning = false
    @State private var quantityFor: Ingredient?
    /// Mode du choix en cours pour un ingrédient : ajout direct ou ajout à la sélection.
    @State private var quantityIsMulti = false

    /// Sélection, dans l'ordre où elle a été faite.
    private enum Pick: Equatable {
        case recipe(Recipe)
        case ingredient(Ingredient, qty: Double)

        var id: PersistentIdentifier {
            switch self {
            case .recipe(let r): r.persistentModelID
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
                Section {
                    Picker("Type", selection: $mode.animation(.snappy)) {
                        Text("Plats").tag("plats")
                        Text("Ingrédients").tag("ingredients")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(selecting ? "Touche pour cocher ou décocher." : "Appui long pour en sélectionner plusieurs.")
                        .padding(.top, 4)
                }
                if mode == "ingredients" { ingredientRows } else { recipeRows }
            }
            .searchable(text: $query, prompt: mode == "ingredients" ? "Rechercher un ingrédient" : "Rechercher un plat")
            .navigationTitle("Ajouter")
            .navigationSubtitle("\(Days.longLabel(ref.date)) · \(Week.slots[ref.slot])")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer", role: .close) { dismiss() } }
                // Créer ou scanner un ingrédient : en icônes, pour garder la liste épurée.
                if mode == "ingredients" {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Nouvel ingrédient", systemImage: "plus") { creatingIngredient = IngredientEditTarget(draft: IngredientDraft()) }
                        Button("Scanner un produit", systemImage: "barcode.viewfinder") { scanning = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !picks.isEmpty {
                    Button(action: commit) {
                        Text("Ajouter \(picks.count) élément\(picks.count > 1 ? "s" : "")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: picks.count)
            .sensoryFeedback(.selection, trigger: picks.count)
            .sheet(isPresented: $creatingRecipe) {
                RecipeEditor(recipe: nil) { r in
                    if selecting { picks.append(.recipe(r)) } else { add([.recipe(r)]) }
                }
            }
            .sheet(item: $creatingIngredient) { t in
                IngredientEditor(target: t) { askQuantity($0, multi: selecting) }
            }
            .barcodeScanFlow(isPresented: $scanning, pickExisting: true) { askQuantity($0, multi: selecting) }
            .sheet(item: $quantityFor) { ing in
                QuantitySheet(ingredient: ing, confirmTitle: quantityIsMulti ? "Sélectionner" : nil) { qty in
                    if quantityIsMulti { picks.append(.ingredient(ing, qty: qty)) } else { add([.ingredient(ing, qty: qty)]) }
                }
            }
        }
    }

    @ViewBuilder
    private func check(_ on: Bool) -> some View {
        if selecting {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? Theme.accent : Theme.muted)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var recipeRows: some View {
        let list = recipes
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        Section {
            ForEach(list) { r in
                let on = isPicked(r.persistentModelID)
                HStack(spacing: 12) {
                    check(on)
                    Text(r.name).foregroundStyle(.primary)
                    Spacer()
                    Text("\(Fmt.n0(r.totals.kcal)) kcal").foregroundStyle(Theme.muted).monospacedDigit()
                }
                .contentShape(.rect)
                .onTapGesture { if selecting { toggle(r) } else { add([.recipe(r)]) } }
                .onLongPressGesture(minimumDuration: 0.35) { if !on { picks.append(.recipe(r)) } }
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction(named: "Sélectionner plusieurs") { if !on { picks.append(.recipe(r)) } }
            }
        }
        Section {
            Button("Créer une nouvelle recette", systemImage: "plus") { creatingRecipe = true }
        }
    }

    @ViewBuilder
    private var ingredientRows: some View {
        let list = ingredients
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ForEach(Rayon.allCases) { rayon in
            let items = list.filter { $0.rayon == rayon }
            if !items.isEmpty {
                Section(rayon.rawValue) {
                    ForEach(items) { i in
                        let qty = pickedQty(i)
                        HStack(spacing: 12) {
                            check(qty != nil)
                            IngredientRow(ingredient: i)
                            if let qty {
                                Text(Fmt.cook(qty, unit: i.unit))
                                    .font(.subheadline.bold()).foregroundStyle(Theme.accent).monospacedDigit()
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture { if selecting { toggle(i) } else { askQuantity(i, multi: false, delay: false) } }
                        .onLongPressGesture(minimumDuration: 0.35) { if qty == nil { askQuantity(i, multi: true, delay: false) } }
                        .accessibilityAddTraits(qty != nil ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction(named: "Sélectionner plusieurs") { if qty == nil { askQuantity(i, multi: true, delay: false) } }
                    }
                }
            }
        }
    }

    private func pickedQty(_ i: Ingredient) -> Double? {
        for p in picks { if case .ingredient(let g, let q) = p, g.persistentModelID == i.persistentModelID { return q } }
        return nil
    }

    private func toggle(_ r: Recipe) {
        if isPicked(r.persistentModelID) { picks.removeAll { $0.id == r.persistentModelID } } else { picks.append(.recipe(r)) }
    }

    private func toggle(_ i: Ingredient) {
        if isPicked(i.persistentModelID) {
            picks.removeAll { $0.id == i.persistentModelID }
        } else {
            askQuantity(i, multi: true, delay: false)
        }
    }

    private func commit() { add(picks) }

    private func add(_ items: [Pick]) {
        for p in items {
            switch p {
            case .recipe(let r): PlanActions.add(r, date: ref.date, slot: ref.slot, in: context)
            case .ingredient(let i, let q): PlanActions.add(i, qty: q, date: ref.date, slot: ref.slot, in: context)
            }
        }
        dismiss()
    }

    /// `delay` : laisse d'abord la fiche ou la caméra se fermer.
    private func askQuantity(_ i: Ingredient, multi: Bool, delay: Bool = true) {
        quantityIsMulti = multi
        Task {
            if delay { try? await Task.sleep(for: .milliseconds(450)) }
            quantityFor = i
        }
    }
}

/// Saisie de la quantité d'un ingrédient seul, avec aperçu des kcal et macros.
struct QuantitySheet: View {
    var ingredient: Ingredient
    var initial: Double? = nil
    var confirmTitle: String? = nil
    /// Explication sous l'aperçu (ex. « Modifie seulement ce plat »).
    var note: String? = nil
    /// Quantité de référence : affiche « Revenir à … » quand on s'en écarte.
    var original: Double? = nil
    var onReset: (() -> Void)? = nil
    var onDone: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var qty: Double? { Fmt.parse(text).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(.title2.bold()).monospacedDigit()
                        Text(ingredient.unit == .pc ? "pièce(s)" : ingredient.unit.short)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Quantité")
                } footer: {
                    let m = ingredient.macros(qty: qty ?? 0)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Fmt.n0(m.kcal)) kcal · \(MacroLine.text(m, unit: " g"))")
                        if let note { Text(note) }
                    }
                }
                if let original, let onReset, initial.map({ abs($0 - original) > 0.001 }) ?? false {
                    Section {
                        Button("Revenir à la recette (\(Fmt.cook(original, unit: ingredient.unit)))",
                               systemImage: "arrow.uturn.backward") {
                            onReset()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(ingredient.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle ?? (initial == nil ? "Ajouter" : "Enregistrer"), role: .confirm) {
                        if let qty { onDone(qty) }
                        dismiss()
                    }
                    .disabled(qty == nil)
                }
            }
        }
        .presentationDetents([.height(original != nil ? 330 : 260)])
        .onAppear {
            text = Fmt.input(initial ?? (ingredient.unit == .pc ? 1 : 100))
            focused = true
        }
    }
}
