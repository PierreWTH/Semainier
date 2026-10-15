import SwiftUI

/// « G 50 · P 32 · L 10 » avec les lettres colorées.
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

/// « 165 kcal · G 0 · P 41 · L 3 » en petit, sous un ingrédient.
struct IngredientMacros: View {
    var m: Macros

    var body: some View {
        Text("\(Fmt.n0(m.kcal)) kcal · \(MacroLine.text(m, unit: " g"))")
            .font(.caption).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Quantité modifiable : pastille teintée ; un point signale une quantité modifiée pour ce plat.
struct QuantityChip: View {
    var text: String
    var modified = false

    var body: some View {
        HStack(spacing: 5) {
            if modified {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    .accessibilityLabel("Modifiée")
            }
            Text(text).monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.accentSoft, in: .capsule)
    }
}

/// Trois barres G / P / L par rapport aux objectifs.
struct MacroBars: View {
    var totals: Macros
    var targets: Macros

    var body: some View {
        HStack(spacing: 12) {
            bar("Glucides", totals.c, targets.c, Theme.carb)
            bar("Protéines", totals.p, targets.p, Theme.prot)
            bar("Lipides", totals.f, targets.f, Theme.fat)
        }
    }

    private func bar(_ label: String, _ v: Double, _ t: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2.weight(.bold)).textCase(.uppercase).kerning(0.6).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.n0(v)).font(.callout.bold())
                Text("/ \(Fmt.n0(t)) g").font(.caption).foregroundStyle(Theme.muted)
            }
            .monospacedDigit()
            // Au-delà de +3 % de l'objectif, la barre passe en rouge brique.
            ProgressBar(fraction: t > 0 ? v / t : 0, color: Nutrition.isOver(v, target: t) ? Theme.over : color)
                .animation(.snappy, value: Nutrition.isOver(v, target: t))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

/// Répartition des kcal entre G / P / L.
struct MacroSplit: View {
    var m: Macros
    var height: CGFloat = 6

    var body: some View {
        let kp = m.p * 4, kc = m.c * 4, kf = m.f * 9
        let total = max(kp + kc + kf, 1)
        GeometryReader { g in
            HStack(spacing: 0) {
                Theme.carb.frame(width: g.size.width * kc / total)
                Theme.prot.frame(width: g.size.width * kp / total)
                Theme.fat.frame(width: g.size.width * kf / total)
            }
        }
        .frame(height: height)
        .background(Theme.surface2)
        .clipShape(.capsule)
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
