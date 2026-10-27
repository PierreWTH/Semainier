import SwiftUI

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
    /// Ingrédient à la pièce : nombre entier, choisi avec − / + comme pour un plat à la pièce.
    @State private var count = 1
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title2) private var unitSize: CGFloat = 22

    private var byPiece: Bool { ingredient.unit == .pc }
    private var qty: Double? { byPiece ? Double(count) : Fmt.parse(text).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        if byPiece {
                            PieceStepper(count: $count)
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                TextField("0", text: $text)
                                    .keyboardType(.decimalPad)
                                    .focused($focused)
                                    .font(.system(size: valueSize, weight: .bold, design: .rounded)).monospacedDigit()
                                Text(ingredient.unit.short)
                                    .font(.system(size: unitSize)).foregroundStyle(Color.textSecondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            // Contour concentrique à la case de la liste : même écart (6 pt) sur les quatre côtés.
                            .overlay(ConcentricRectangle()
                                .stroke(focused ? Color.accentColor : .clear, lineWidth: 2)
                                .padding(1))
                            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                        }
                    } header: {
                        Text(byPiece ? "Nombre de pièces" : "Quantité")
                    } footer: {
                        let m = ingredient.macros(qty: qty ?? 0)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(Fmt.n0(m.kcal)) kcal · \(MacroLine.text(m, unit: " g"))")
                                .font(.subheadline).foregroundStyle(Color.textSecondary)
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
                .listRowBackground(Color.surface)
            }
            .screenBackground()
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
        .presentationDetents([.height((byPiece ? 340 : 210) + (original != nil ? 70 : 0))])
        .presentationBackground(Color.appBackground)
        .onAppear {
            text = Fmt.input(initial ?? (byPiece ? 1 : 100))
            count = max(1, Int((initial ?? 1).rounded()))
            if !byPiece { focused = true }
        }
    }
}
