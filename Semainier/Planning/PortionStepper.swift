import SwiftUI

/// Stepper −/+ de la portion, par pas de 0,1. Retiré de l'écran pour l'instant, gardé pour plus tard.
struct PortionStepper: View {
    @Binding var x: Double

    var body: some View {
        HStack(spacing: 0) {
            Button("Réduire la portion", systemImage: "minus") { x = Nutrition.stepped(x, by: -1) }
                .disabled(x <= 0.1)
            Text(Fmt.x(x))
                .font(.footnote.bold()).monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText(value: x))
            Button("Augmenter la portion", systemImage: "plus") { x = Nutrition.stepped(x, by: 1) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.subheadline.bold())
        .buttonRepeatBehavior(.enabled)
        .frame(height: 34)
        .padding(.horizontal, 8)
        .background(Color.fond, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.filet))
        .sensoryFeedback(.increase, trigger: x)
        .animation(.snappy, value: x)
    }
}
