import SwiftUI

/// Nombre de pièces d'un plat qui se compte à la pièce (« 2 burgers ») : −/+ et raccourcis 1 · 2 · 3.
/// Nombres entiers uniquement.
struct PieceCountSheet: View {
    var recipe: Recipe
    /// Nombre actuel (modification) ; nil pour un ajout.
    var initial: Int? = nil
    var confirmTitle: String? = nil
    var onDone: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var count = 1

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        PieceStepper(count: $count)
                    } header: {
                        Text("Nombre de pièces")
                    } footer: {
                        let m = recipe.totals * Double(count)
                        Text("\(Fmt.n0(m.kcal)) kcal · \(MacroLine.text(m, unit: " g"))")
                            .font(.subheadline).foregroundStyle(Color.texte2)
                    }
                }
                .listRowBackground(Color.surface)
            }
            .fondEcran()
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle ?? (initial == nil ? "Ajouter" : "Enregistrer"), role: .confirm) {
                        onDone(count)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(330)])
        .presentationBackground(Color.fond)
        .onAppear { count = max(1, initial ?? 1) }
    }
}

/// « − 2 pièces + » puis raccourcis 1 · 2 · 3 : nombre entier de pièces (plat ou ingrédient à la pièce).
struct PieceStepper: View {
    @Binding var count: Int
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title2) private var unitSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title2) private var stepSize: CGFloat = 44

    private static let shortcuts = [1, 2, 3]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                step("Une pièce de moins", "minus", -1).disabled(count <= 1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)")
                        .font(.system(size: valueSize, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                    Text(count > 1 ? "pièces" : "pièce")
                        .font(.system(size: unitSize)).foregroundStyle(Color.texte2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                step("Une pièce de plus", "plus", 1).disabled(count >= 99)
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                ForEach(Self.shortcuts, id: \.self) { n in
                    let on = count == n
                    Button { withAnimation(.snappy) { count = n } } label: {
                        Text("\(n)")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? Color.surAccent : Color.accentColor)
                            .background(on ? Color.accentColor : Color.accentDoux,
                                        in: .rect(cornerRadius: Arrondi.pastille))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Fmt.pieces(Double(n)))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: count)
    }

    /// Le cercle fait partie du bouton : toute sa surface est tactile, pas seulement le signe « − ».
    private func step(_ label: String, _ icon: String, _ delta: Int) -> some View {
        Button { withAnimation(.snappy) { count += delta } } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .frame(width: stepSize, height: stepSize)
                .background(Color.accentDoux, in: .circle)
                .contentShape(.circle)
        }
        .foregroundStyle(Color.accentColor)
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}
