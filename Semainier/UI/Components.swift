import SwiftUI

/// « G 50 · P 32 · L 10 » : la lettre porte la couleur de la macro, le chiffre reste en couleur texte.
struct MacroLine: View {
    var m: Macros
    var unit = ""

    var body: some View { Self.text(m, unit: unit) }

    static func text(_ m: Macros, unit: String = "") -> Text {
        Text("\(letter(.glucides)) \(Fmt.n0(m.c)) · \(letter(.proteines)) \(Fmt.n0(m.p)) · \(letter(.lipides)) \(Fmt.n0(m.f))\(unit)")
            .monospacedDigit()
    }

    static func letter(_ macro: Macro) -> Text {
        Text(macro.lettre).bold().foregroundStyle(macro.texte)
    }
}

/// « 165 kcal · G 0 · P 41 · L 3 g » en petit, sous un ingrédient.
struct IngredientMacros: View {
    var m: Macros

    var body: some View {
        Text("\(Fmt.n0(m.kcal)) kcal · \(MacroLine.text(m, unit: " g"))")
            .font(.footnote).foregroundStyle(Color.texte2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pastille de quantité d'un ingrédient de plat déplié. Toute la ligne est touchable (au moins 44 pt de haut).
/// Un point signale une quantité modifiée pour ce plat.
struct QuantityChip: View {
    var text: String
    var modified = false
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13.5

    var body: some View {
        HStack(spacing: 5) {
            if modified {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    .accessibilityLabel("Modifiée")
            }
            quantity
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 10)
        .frame(minWidth: 54, minHeight: 28)
        .background(Color.accentDoux, in: .rect(cornerRadius: 8))
    }

    /// Le nombre en Semibold, l'unité (« g », « pièces ») en Regular.
    private var quantity: Text {
        let q = QuantityParts(text)
        guard let unit = q.unit else { return Text(q.number) }
        return Text("\(Text(q.number)) \(Text(unit).fontWeight(.regular))")
    }
}

/// « 250 g » → nombre « 250 » et unité « g », pour les styler séparément.
struct QuantityParts {
    var number: String
    var unit: String?

    init(_ text: String) {
        if let i = text.firstIndex(of: " ") {
            number = String(text[..<i])
            unit = String(text[text.index(after: i)...])
        } else {
            number = text
        }
    }
}

/// Cercle de sélection : contour 1,5 pt `texte3`, ou accent plein avec une coche.
struct CercleCoche: View {
    var on: Bool
    var size: CGFloat = 24
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            if on {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark")
                    .font(.system(size: size * scale * 0.5, weight: .bold))
                    .foregroundStyle(Color.surAccent)
            } else {
                Circle().strokeBorder(Color.texte3, lineWidth: 1.5)
            }
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true)
    }
}

/// Les trois macros de la carte total, une ligne par colonne : « G 259 / 310 g », puis la barre de 4 pt.
/// Aux tailles d'accessibilité, les colonnes passent en lignes.
struct MacroBars: View {
    var totals: Macros
    var targets: Macros
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var letterSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var unitSize: CGFloat = 12

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            bar(.glucides, totals.c, targets.c)
            bar(.proteines, totals.p, targets.p)
            bar(.lipides, totals.f, targets.f)
        }
    }

    private func bar(_ macro: Macro, _ v: Double, _ t: Double) -> some View {
        let over = Seuil.depasse(v, objectif: t)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(macro.lettre).font(.system(size: letterSize, weight: .bold)).foregroundStyle(macro.texte)
                Text(Fmt.n0(v)).police(.valeurMacroCarte)
                    .foregroundStyle(over ? Color.depassement : v > 0 ? Color.texte : Color.texte3)
                    .contentTransition(.numericText(value: v))
                Text("/ \(Fmt.n0(t)) g").font(.system(size: unitSize)).foregroundStyle(Color.texte2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
            BarreObjectif(valeur: v, objectif: t, couleur: macro.trait, piste: .pisteCarteTotal, hauteur: 4)
                .animation(.snappy, value: v)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Le libellé visible n'est plus qu'une lettre : VoiceOver lit le nom complet.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.libelle) \(Fmt.n0(v)) sur \(Fmt.n0(t)) grammes")
        .accessibilityValue(over ? "objectif dépassé" : "")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Petit message temporaire en bas de l'écran.
@Observable
final class Toast {
    var message: String?
    private var task: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { message = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @Environment(Toast.self) private var toast

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = toast.message {
                Text(m)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast.message)
    }
}
