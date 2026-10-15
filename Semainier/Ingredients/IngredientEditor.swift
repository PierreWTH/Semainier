import SwiftData
import SwiftUI

/// Brouillon d'ingrédient (saisie, ou préremplissage après un scan).
struct IngredientDraft {
    var name = ""
    var unit: Unit = .g
    var kcal = ""
    var p = ""
    var c = ""
    var f = ""
    var rayon: Rayon = .epicerie
    var barcode: String?
    /// Kcal corrigées au scan (fiche Open Food Facts incohérente).
    var kcalNote: String?
    /// Poids (ou volume) d'une pièce, en g ou ml : sert à convertir « pour 100 g » ↔ « par pièce ».
    var pieceWeight = ""
    /// Valeurs pour 100 g / 100 ml mises de côté pendant la saisie, pour recalculer sans cumuler d'arrondis.
    private var base100: [Double?]?

    init(barcode: String? = nil) { self.barcode = barcode }

    private var values: [Double?] {
        get { [kcal, p, c, f].map(Fmt.parse) }
        set {
            let s = newValue.map { $0.map { Fmt.input(($0 * 100).rounded() / 100) } ?? "" }
            kcal = s[0]; p = s[1]; c = s[2]; f = s[3]
        }
    }

    private var weight: Double { Fmt.parse(pieceWeight) ?? 0 }

    /// Change d'unité en convertissant les valeurs quand on connaît le poids d'une pièce.
    mutating func setUnit(_ new: Unit) {
        let old = unit
        unit = new
        switch (old == .pc, new == .pc) {
        case (false, true):
            base100 = values
            if weight > 0 { values = base100!.map { $0.map { $0 * weight / 100 } } }
        case (true, false):
            if let base100 { values = base100 } else if weight > 0 { values = values.map { $0.map { $0 * 100 / weight } } }
            base100 = nil
        default:
            break
        }
    }

    /// Change le poids d'une pièce : les valeurs par pièce suivent.
    mutating func setPieceWeight(_ text: String) {
        let old = weight
        pieceWeight = text
        guard unit == .pc else { return }
        if base100 == nil, old > 0 { base100 = values.map { $0.map { $0 * 100 / old } } }
        if let base100, weight > 0 { values = base100.map { $0.map { $0 * weight / 100 } } }
    }

    /// Une valeur tapée à la main : on oublie la base pour 100 g, la saisie fait foi.
    mutating func valuesEdited() { base100 = nil }

    init(_ i: Ingredient) {
        name = i.name
        unit = i.unit
        kcal = Fmt.input(i.kcal)
        p = Fmt.input(i.p)
        c = Fmt.input(i.c)
        f = Fmt.input(i.f)
        rayon = i.rayon
        barcode = i.barcode
        pieceWeight = Fmt.input(i.pieceWeight)
    }

    init(scanned s: ScannedProduct, barcode: String) {
        name = s.name
        unit = s.unit
        kcal = s.kcal.map(Fmt.input) ?? ""
        p = s.p.map(Fmt.input) ?? ""
        c = s.c.map(Fmt.input) ?? ""
        f = s.f.map(Fmt.input) ?? ""
        rayon = s.rayon
        self.barcode = barcode
        kcalNote = s.kcalNote
        pieceWeight = s.pieceWeight.map(Fmt.input) ?? ""
    }

    var macros: (p: Double, c: Double, f: Double) {
        (Fmt.parse(p) ?? 0, Fmt.parse(c) ?? 0, Fmt.parse(f) ?? 0)
    }

    /// Kcal saisies, ou 4P + 4G + 9L si le champ est vide.
    var resolvedKcal: Double {
        if let k = Fmt.parse(kcal) { return k }
        let m = macros
        return (m.p * 4 + m.c * 4 + m.f * 9).rounded()
    }
}

/// Contexte d'un scan, pour proposer d'autres résultats si le premier n'est pas le bon.
struct ScanContext {
    var code: String
    var initial: IngredientDraft
    /// Termes de recherche (nom + marque du produit scanné), vides si le code est inconnu.
    var terms: String
}

struct IngredientEditTarget: Identifiable {
    let id = UUID()
    var ingredient: Ingredient?
    var draft: IngredientDraft?
    var note: String?
    var scan: ScanContext?
}

struct IngredientEditor: View {
    var target: IngredientEditTarget
    var onSaved: ((Ingredient) -> Void)?
    var onRescan: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var d = IngredientDraft()
    @State private var loaded = false
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool
    @State private var alternatives: [ScannedProduct]?
    @State private var altIndex = 0
    @State private var altLoading = false
    @State private var altMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let note = target.note {
                    Section { Label(note, systemImage: "barcode.viewfinder").font(.subheadline) }
                }
                if let scan = target.scan, target.ingredient == nil {
                    scanSection(scan)
                }
                Section("Nom") {
                    TextField("Ex. Flocons d'avoine", text: $d.name)
                        .focused($nameFocused)
                }
                Section {
                    Picker("Valeurs données", selection: Binding(get: { d.unit }, set: { d.setUnit($0) })) {
                        ForEach(Unit.allCases) { u in
                            Text(u.per.capitalizedFirst).tag(u)
                        }
                    }
                    if d.unit == .pc {
                        NumberField(label: "Poids d'une pièce",
                                    text: Binding(get: { d.pieceWeight }, set: { d.setPieceWeight($0) }),
                                    placeholder: "ex. 300")
                    }
                    NumberField(label: "Kcal", text: manual(\.kcal), placeholder: kcalPlaceholder)
                    NumberField(label: "Glucides (g)", text: manual(\.c), color: Theme.carb)
                    NumberField(label: "Protéines (g)", text: manual(\.p), color: Theme.prot)
                    NumberField(label: "Lipides (g)", text: manual(\.f), color: Theme.fat)
                } header: {
                    Text("Valeurs nutritionnelles")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if d.unit == .pc, let w = Fmt.parse(d.pieceWeight), w > 0 {
                            Text("Valeurs pour 1 pièce de \(Fmt.n1(w)) g, calculées à partir des valeurs pour 100 g.")
                        }
                        if let note = d.kcalNote { Text(note).foregroundStyle(Theme.warn) }
                        Text(hint).foregroundStyle(kcalLooksOff ? Theme.warn : Theme.muted)
                    }
                }
                Section {
                    Picker("Rayon", selection: $d.rayon) {
                        ForEach(Rayon.allCases) { Text($0.rawValue).tag($0) }
                    }
                } footer: {
                    Text("Sert à trier la liste de courses.")
                }
                if let code = d.barcode {
                    Section("Code-barres") {
                        LabeledContent("EAN", value: code).monospacedDigit()
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.bad).font(.subheadline.weight(.semibold))
                }
                if let ing = target.ingredient {
                    Section {
                        Button("Supprimer l'ingrédient", role: .destructive) { confirmDelete = true }
                    } footer: {
                        let n = ing.recipeCount
                        if n > 0 { Text("Il est utilisé dans \(n) recette\(n > 1 ? "s" : "").") }
                    }
                }
            }
            .navigationTitle(target.ingredient == nil ? "Nouvel ingrédient" : "Modifier l'ingrédient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", role: .confirm, action: save) }
            }
            .confirmationDialog("Supprimer cet ingrédient ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(deleteLabel, role: .destructive) {
                    if let ing = target.ingredient { PlanActions.delete(ing, settings: settings, in: context) }
                    toast.show("Ingrédient supprimé")
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let i = target.ingredient { d = IngredientDraft(i) } else if let draft = target.draft { d = draft }
            if target.ingredient == nil && d.name.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    nameFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private func scanSection(_ scan: ScanContext) -> some View {
        let total = (alternatives?.count ?? 0) + 1
        Section {
            if altIndex > 0, let alt = alternatives?[altIndex - 1] {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Résultat \(altIndex + 1) / \(total)").font(.caption.bold()).foregroundStyle(Theme.accent)
                    Text([alt.name, alt.quantity].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                }
            }
            Button {
                Task { await nextResult(scan) }
            } label: {
                HStack {
                    Label(altIndex > 0 && altIndex == total - 1 ? "Revenir au premier résultat" : "Résultat suivant",
                          systemImage: altIndex > 0 && altIndex == total - 1 ? "arrow.uturn.backward" : "arrow.forward.circle")
                    Spacer()
                    if altLoading { ProgressView() }
                }
            }
            .disabled(altLoading || searchTerms(scan).isEmpty)
            if let onRescan {
                Button("Rescanner", systemImage: "barcode.viewfinder", action: onRescan)
            }
        } header: {
            Text("Pas le bon produit ?")
        } footer: {
            Text(altMessage ?? (searchTerms(scan).isEmpty
                ? "Tape un nom ci-dessous pour chercher des produits proches sur Open Food Facts."
                : "Propose des produits proches sur Open Food Facts (autres formats, même marque). Le code-barres scanné est conservé."))
        }
    }

    private func searchTerms(_ scan: ScanContext) -> String {
        let t = scan.terms.isEmpty ? d.name : scan.terms
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Passe au produit proche suivant ; la liste est chargée au premier appui, puis reboucle sur le scan d'origine.
    private func nextResult(_ scan: ScanContext) async {
        if alternatives == nil {
            altLoading = true
            defer { altLoading = false }
            do {
                alternatives = try await OpenFoodFacts.search(searchTerms(scan), excluding: scan.code)
            } catch {
                altMessage = "Pas de connexion : impossible de chercher d'autres résultats."
                return
            }
        }
        guard let alts = alternatives, !alts.isEmpty else {
            altMessage = "Aucun autre produit proche trouvé. Essaie de rescanner, ou corrige les valeurs à la main."
            return
        }
        altMessage = nil
        withAnimation(.snappy) {
            altIndex = (altIndex + 1) % (alts.count + 1)
            d = altIndex == 0 ? scan.initial : IngredientDraft(scanned: alts[altIndex - 1], barcode: scan.code)
        }
    }

    private var kcalPlaceholder: String {
        let m = d.macros
        let est = m.p * 4 + m.c * 4 + m.f * 9
        return est > 0 ? Fmt.n0(est) : "0"
    }

    /// Champ de valeur saisi à la main (oublie la base pour 100 g gardée pour les conversions).
    private func manual(_ field: WritableKeyPath<IngredientDraft, String>) -> Binding<String> {
        Binding(get: { d[keyPath: field] }, set: { d[keyPath: field] = $0; d.valuesEdited() })
    }

    private var kcalLooksOff: Bool {
        let m = d.macros
        guard let k = Fmt.parse(d.kcal) else { return false }
        return Nutrition.kcalLooksOff(kcal: k, macroKcal: m.p * 4 + m.c * 4 + m.f * 9)
    }

    private var hint: String {
        let m = d.macros
        let est = m.p * 4 + m.c * 4 + m.f * 9
        if let k = Fmt.parse(d.kcal), Nutrition.kcalLooksOff(kcal: k, macroKcal: est) {
            return "⚠︎ \(Fmt.n0(k)) kcal ne colle pas avec les macros (environ \(Fmt.n0(est)) kcal). Vérifie l'étiquette, ou laisse « Kcal » vide pour utiliser le calcul."
        }
        if est > 0 {
            return "D'après les macros : environ \(Fmt.n0(est)) kcal. Laisse « Kcal » vide pour utiliser ce calcul."
        }
        return "Recopie les valeurs de l'étiquette ou d'une table nutritionnelle (Ciqual par exemple), \(d.unit.per)."
    }

    private var deleteLabel: String {
        guard let ing = target.ingredient, ing.recipeCount > 0 || ing.planCount > 0 else { return "Supprimer" }
        return "Supprimer (\(IngredientsView.usageText(ing)))"
    }

    private func save() {
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Donne un nom à l'ingrédient."; nameFocused = true; return }
        let m = d.macros
        let ing: Ingredient
        if let existing = target.ingredient {
            ing = existing
            ing.name = name
            ing.unit = d.unit
            ing.kcal = d.resolvedKcal
            ing.p = m.p
            ing.c = m.c
            ing.f = m.f
            ing.rayon = d.rayon
            ing.barcode = d.barcode
        } else {
            ing = Ingredient(name: name, unit: d.unit, kcal: d.resolvedKcal, p: m.p, c: m.c, f: m.f,
                             rayon: d.rayon, barcode: d.barcode)
            context.insert(ing)
        }
        ing.pieceWeight = Fmt.parse(d.pieceWeight) ?? 0
        toast.show(target.ingredient == nil ? "Ingrédient ajouté" : "Ingrédient mis à jour")
        dismiss()
        onSaved?(ing)
    }
}
