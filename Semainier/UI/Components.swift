import SwiftUI

/// « G 50 · P 32 · L 10 » : lettres colorées en gras, valeurs en chiffres tabulaires.
struct MacroLine: View {
    var m: Macros
    var unit = ""

    var body: some View { Self.text(m, unit: unit) }

    static func text(_ m: Macros, unit: String = "") -> Text {
        Text("\(letter("G", Theme.carb)) \(Fmt.n0(m.c)) · \(letter("P", Theme.prot)) \(Fmt.n0(m.p)) · \(letter("L", Theme.fat)) \(Fmt.n0(m.f))\(unit)")
            .monospacedDigit()
    }

    private static func letter(_ s: String, _ c: Color) -> Text {
        Text(s).bold().foregroundStyle(c)
    }
}

/// « 294 kcal · G 47 · P 11 · L 6 » : le chiffre des kcal en gras, le reste en méta.
struct IngredientMacros: View {
    var m: Macros
    var unit = ""
    var alignment: Alignment = .leading

    var body: some View {
        Text("\(Text(Fmt.n0(m.kcal)).fontWeight(.semibold).foregroundStyle(Theme.ink)) kcal · \(MacroLine.text(m, unit: unit))")
            .font(.meta).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// Pastille de quantité touchable : capsule accent doux + petite plume ✎. Cible tactile de 44 pt.
/// Un point signale une quantité modifiée pour ce plat.
struct QuantityChip: View {
    var text: String
    var modified = false

    var body: some View {
        HStack(spacing: 5) {
            if modified {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    .accessibilityLabel("Modifiée")
            }
            Text(text).font(.callout.weight(.semibold).width(.expanded)).monospacedDigit()
            Image(systemName: "pencil").font(.caption2.weight(.semibold)).opacity(0.7)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Theme.accentSoft, in: .capsule)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

/// Trois jauges G / P / L par rapport aux objectifs ; au-delà de +3 %, le dépassement
/// apparaît en segment brique séparé et en « +8 » à côté du libellé.
struct MacroBars: View {
    var totals: Macros
    var targets: Macros

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            bar("Glucides", totals.c, targets.c, Theme.carb)
            bar("Protéines", totals.p, targets.p, Theme.prot)
            bar("Lipides", totals.f, targets.f, Theme.fat)
        }
    }

    private func bar(_ label: String, _ v: Double, _ t: Double, _ color: Color) -> some View {
        let over = Nutrition.isOver(v, target: t)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).sectionLabel(color)
                if over {
                    Text("+\(Fmt.n0(v - t))").font(.label).foregroundStyle(Theme.over)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Fmt.n0(v)).font(.strongNumber).foregroundStyle(over ? Theme.over : Theme.ink)
                Text("/\(Fmt.n0(t)) g").font(.caption).foregroundStyle(Theme.muted)
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            MacroGauge(value: v, target: t, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Jauge de 6 pt : remplie jusqu'à l'objectif ; un dépassement s'ajoute en segment brique, séparé de 2 pt.
struct MacroGauge: View {
    var value: Double
    var target: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        let over = Nutrition.isOver(value, target: target)
        GeometryReader { g in
            let w = g.size.width
            if over {
                // Proportion objectif / dépassement sur toute la largeur.
                let main = w * target / value
                HStack(spacing: 2) {
                    Capsule().fill(color).frame(width: max(main - 2, 0))
                    Capsule().fill(Theme.over)
                }
            } else {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(color).frame(width: w * min(max(target > 0 ? value / target : 0, 0), 1))
                }
            }
        }
        .frame(height: height)
        .animation(.snappy, value: value)
    }
}

/// Jauge simple (kcal, panier) : capsule de couleur sur une piste surface 2.
struct ProgressBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        Capsule().fill(Theme.surface2)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(color).frame(width: g.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(.capsule)
    }
}

/// Barre de répartition des kcal G / P / L : segments séparés de 2 pt.
struct MacroSplit: View {
    var m: Macros
    var height: CGFloat = 6

    var body: some View {
        let kp = m.p * 4, kc = m.c * 4, kf = m.f * 9
        let total = max(kp + kc + kf, 1)
        GeometryReader { g in
            let w = g.size.width - 4
            HStack(spacing: 2) {
                Capsule().fill(Theme.carb).frame(width: max(w * kc / total, 0))
                Capsule().fill(Theme.prot).frame(width: max(w * kp / total, 0))
                Capsule().fill(Theme.fat).frame(width: max(w * kf / total, 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Bouton principal : capsule faïence pleine.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(Theme.accent, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Coche ronde (courses, sélection) : cercle cerné, ou rempli faïence avec la coche.
struct CheckCircle: View {
    var on: Bool
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.line, lineWidth: 2).opacity(on ? 0 : 1)
            Circle().fill(Theme.accent).opacity(on ? 1 : 0)
            Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(Theme.onAccent).opacity(on ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: on)
    }
}

/// Étiquette d'unité (« PIÈCE », « 100 G ») en mono, sur fond surface 2.
struct UnitTag: View {
    var text: String

    var body: some View {
        Text(text).font(.system(size: 9, weight: .medium).monospaced()).textCase(.uppercase).kerning(0.5)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Theme.surface2, in: .rect(cornerRadius: 4))
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
