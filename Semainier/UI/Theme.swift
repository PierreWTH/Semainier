import SwiftUI
import UIKit

/// Palette reprise de la maquette, en clair et en sombre.
enum Theme {
    static let bg = Color(light: 0xF2F4F0, dark: 0x111614)
    static let surface = Color(light: 0xFFFFFF, dark: 0x19201D)
    static let surface2 = Color(light: 0xE7EBE4, dark: 0x232C28)
    static let line = Color(light: 0xD4DBD0, dark: 0x2E3934)
    static let muted = Color(light: 0x5B6861, dark: 0x97A59D)
    static let accent = Color(light: 0x23466E, dark: 0x93B7E2)
    static let accentSoft = Color(light: 0xDCE5F0, dark: 0x1D2E43)
    static let prot = Color(light: 0xB8385A, dark: 0xE57A93)
    static let carb = Color(light: 0xBD820C, dark: 0xE2AE48)
    static let fat = Color(light: 0x727C26, dark: 0xB4BE59)
    static let ok = Color(light: 0x2C7A4C, dark: 0x5EBC86)
    static let warn = Color(light: 0xB26210, dark: 0xE59D4E)
    static let bad = Color(light: 0xB23A30, dark: 0xE7786D)
    /// Dépassement de l'objectif : rouge brique adouci, moins vif que `bad`.
    static let over = Color(light: 0xB65A4F, dark: 0xD9857A)

    static func color(_ s: DayStatus) -> Color {
        switch s {
        case .ok: ok
        case .warn: warn
        case .bad: bad
        case .none: muted
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Carte : fond surface, bord fin, coins arrondis.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.line))
    }
}

extension View {
    func card(radius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }

    /// Titre de section en petites capitales grises.
    func sectionLabel() -> some View {
        font(.caption.weight(.bold)).textCase(.uppercase).kerning(0.8).foregroundStyle(Theme.muted)
    }
}
