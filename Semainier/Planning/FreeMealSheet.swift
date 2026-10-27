import SwiftUI

/// Saisie d'un repas libre : un nom, les kcal estimées (raccourcis 500 · 800 · 1 000 · 1 500),
/// et les macros en option.
struct FreeMealSheet: View {
    /// Repas à modifier ; nil pour en ajouter un.
    var initial: FreeMeal? = nil
    /// Nom proposé à l'ouverture (ex. le texte cherché dans « Ajouter »).
    var suggestedName = ""
    var onDone: (FreeMeal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcalText = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var showsMacros = false
    @FocusState private var kcalFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title2) private var unitSize: CGFloat = 22

    private static let shortcuts: [Double] = [500, 800, 1000, 1500]

    private var kcal: Double? { Fmt.parse(kcalText).flatMap { $0 > 0 ? $0 : nil } }

    private var meal: FreeMeal? {
        guard let kcal else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return FreeMeal(name: trimmed.isEmpty ? FreeMeal.defaultName : trimmed, kcal: kcal,
                        p: Fmt.parse(p) ?? 0, c: Fmt.parse(c) ?? 0, f: Fmt.parse(f) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Nom") {
                        TextField(FreeMeal.defaultName, text: $name)
                            .submitLabel(.next)
                            .onSubmit { kcalFocused = true }
                    }

                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("≈").font(.system(size: unitSize, weight: .semibold)).foregroundStyle(Color.freeMeal)
                            TextField("0", text: $kcalText)
                                .keyboardType(.numberPad)
                                .focused($kcalFocused)
                                .font(.system(size: valueSize, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("kcal").font(.system(size: unitSize)).foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip)
                            .strokeBorder(kcalFocused ? Color.accentColor : .clear, lineWidth: 2))
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))

                        HStack(spacing: 8) {
                            ForEach(Self.shortcuts, id: \.self) { v in
                                let on = kcal == v
                                Button { kcalText = Fmt.input(v) } label: {
                                    Text(Fmt.n0(v))
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .monospacedDigit()
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .foregroundStyle(on ? Color.onAccent : Color.accentColor)
                                        .background(on ? Color.accentColor : Color.accentSoft,
                                                    in: .rect(cornerRadius: Radius.chip))
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(Fmt.n0(v)) kilocalories")
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .sensoryFeedback(.selection, trigger: kcal)
                    } header: {
                        Text("Calories estimées")
                    } footer: {
                        Text("Une estimation suffit : elle compte dans le total du jour, pas dans la liste de courses.")
                    }

                    Section {
                        DisclosureGroup("Préciser les macros", isExpanded: $showsMacros.animation(.snappy)) {
                            NumberField(label: "Glucides (g)", text: $c, color: Color.carbsText)
                            NumberField(label: "Protéines (g)", text: $p, color: Color.proteinText)
                            NumberField(label: "Lipides (g)", text: $f, color: Color.fatText)
                        }
                    } footer: {
                        if showsMacros, let hint = macrosHint { Text(hint) }
                    }
                }
                .listRowBackground(Color.surface)
            }
            .screenBackground()
            .navigationTitle(FreeMeal.defaultName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(initial == nil ? "Ajouter" : "Enregistrer", role: .confirm) {
                        if let meal { onDone(meal) }
                        dismiss()
                    }
                    .disabled(meal == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.appBackground)
        .onAppear {
            if let initial {
                name = initial.name == FreeMeal.defaultName ? "" : initial.name
                kcalText = Fmt.input(initial.kcal)
                if initial.hasMacros {
                    p = Fmt.input(initial.p); c = Fmt.input(initial.c); f = Fmt.input(initial.f)
                    showsMacros = true
                }
            } else {
                name = suggestedName
            }
            kcalFocused = true
        }
    }

    /// « Ces macros font ≈ 1 050 kcal. » quand elles s'écartent nettement de l'estimation.
    private var macrosHint: String? {
        let fromMacros = Macros(p: Fmt.parse(p) ?? 0, c: Fmt.parse(c) ?? 0, f: Fmt.parse(f) ?? 0).kcalFromMacros
        guard fromMacros > 0 else { return "Facultatif. Sans macros, seules les kcal comptent." }
        guard let kcal, abs(fromMacros - kcal) / kcal > 0.15 else { return nil }
        return "Ces macros font ≈ \(Fmt.n0(fromMacros)) kcal."
    }
}

/// Signes communs du repas libre dans les vues Jour et Semaine.
enum FreeMealStyle {
    static let icon = "takeoutbag.and.cup.and.straw"

    /// « ≈ 1 200 kcal »
    static func kcal(_ m: FreeMeal) -> String { "≈ \(Fmt.n0(m.kcal)) kcal" }
}
