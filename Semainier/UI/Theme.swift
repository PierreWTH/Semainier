import SwiftUI
import UIKit

/// Direction artistique « Étiquette & faïence » : papier crème, encre brune, bleu faïence.
/// La précision d'une étiquette nutritionnelle, la chaleur d'une cuisine.
enum Theme {
    // Papier et encre
    static let bg = Color(light: 0xF4EFE6, dark: 0x15120E)          // Fond (papier)
    static let surface = Color(light: 0xFFFDF8, dark: 0x1F1B16)     // Surface (cartes)
    static let surface2 = Color(light: 0xEBE4D6, dark: 0x2A251E)    // Surface 2 (puces, cases)
    static let line = Color(light: 0xDCD2C0, dark: 0x3A3329)        // Trait
    static let ink = Color(light: 0x1E1A15, dark: 0xF2EBDF)         // Texte (encre), filet des étiquettes
    static let muted = Color(light: 0x665D51, dark: 0xABA08F)       // Texte secondaire

    // Faïence
    static let accent = Color(light: 0x2B4E9B, dark: 0x9DB4EC)
    static let accentSoft = Color(light: 0xE2E7F3, dark: 0x1F2B47)
    /// Teinte très légère (colonne du jour, ligne sélectionnée).
    static let accentWash = Color(light: 0x2B4E9B, dark: 0x9DB4EC).opacity(0.065)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x10182E)

    // Macros : blé, betterave, olive (luminances distinctes pour les daltoniens)
    static let carb = Color(light: 0x9A6508, dark: 0xE2B04E)
    static let prot = Color(light: 0xA12F5A, dark: 0xEC86A6)
    static let fat = Color(light: 0x5C7322, dark: 0xAEC46A)

    // États
    static let over = Color(light: 0xAE4E3B, dark: 0xE58C79)        // Dépassement · brique
    static let overSoft = Color(light: 0xF5E1DA, dark: 0x3A221C)
    static let ok = Color(light: 0x2F7650, dark: 0x6CC08F)          // Dans la cible
    /// Attention (fiche incohérente) : ambre, distinct de la brique.
    static let warn = Color(light: 0xA35C12, dark: 0xE59D4E)
    /// Erreur de saisie : la brique.
    static let bad = over

    /// Jauge d'un jour : sous la cible = encre, dans ±3 % = vert, au-delà = brique.
    static func gauge(kcal: Double, target: Double) -> Color {
        guard target > 0, kcal > 0 else { return surface2 }
        let r = kcal / target
        return r > 1.03 ? over : r >= 0.97 ? ok : ink
    }

    static func color(_ s: DayStatus) -> Color {
        switch s {
        case .ok: ok
        case .warn, .bad: over
        case .none: muted
        }
    }

    // Rayons et espacements (base 4)
    enum Radius {
        static let micro: CGFloat = 3     // micro-barres
        static let cell: CGFloat = 10     // cases de la semaine, puces
        static let field: CGFloat = 14    // champs de saisie
        static let card: CGFloat = 20     // cartes, listes groupées
    }

    /// Épaisseur du filet qui ouvre chaque bloc de total, comme sur une étiquette.
    static let rule: CGFloat = 3
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    convenience init(light: UInt32, dark: UInt32) {
        self.init { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

// MARK: - Typographie : SF Pro Expanded pour les chiffres, SF Mono pour les étiquettes

extension Font {
    /// Chiffre fort : Expanded Semibold 20 (grammes, kcal d'un repas).
    static let strongNumber = Font.title3.weight(.semibold).width(.expanded).monospacedDigit()
    /// Méta : Regular 13 tabulaire (« 294 kcal · G 47 · P 11 · L 6 g »).
    static let meta = Font.footnote.monospacedDigit()
    /// Étiquette : SF Mono Medium 11, en capitales espacées (« PETIT-DÉJEUNER »).
    static let label = Font.caption2.monospaced().weight(.medium)
}

/// Chiffre héros (Expanded Bold 48), qui suit la taille de texte de l'utilisateur.
struct HeroNumber: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 48
    var base: CGFloat = 48

    func body(content: Content) -> some View {
        content.font(.system(size: size * base / 48, weight: .bold).width(.expanded).monospacedDigit())
    }
}

/// Carte : surface mate, sans ombre, coins de 20 pt, trait fin.
struct CardStyle: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.line.opacity(0.7)))
    }
}

extension View {
    func card(radius: CGFloat = Theme.Radius.card, padding: CGFloat = 16) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }

    func heroNumber(_ size: CGFloat = 48) -> some View { modifier(HeroNumber(base: size)) }

    /// Étiquette en SF Mono capitales espacées, couleur secondaire.
    func sectionLabel(_ color: Color = Theme.muted) -> some View {
        font(.label).textCase(.uppercase).kerning(0.8).foregroundStyle(color)
    }

    /// Liste ou formulaire posé sur le papier : fond crème, lignes en surface.
    func paperList() -> some View {
        scrollContentBackground(.hidden).background(Theme.bg)
    }
}

/// Filet épais qui ouvre un bloc de total, comme sur une étiquette.
struct LabelRule: View {
    var body: some View { Rectangle().fill(Theme.ink).frame(height: Theme.rule) }
}

/// En-tête de section de liste en SF Mono capitales, avec un éventuel compteur à droite.
struct ListHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title).sectionLabel()
            Spacer()
            if let trailing { Text(trailing).sectionLabel() }
        }
    }
}

enum Appearance {
    /// Grands titres en SF Pro Expanded Bold, couleur encre. Le verre des barres reste celui du système.
    static func apply() {
        let ink = UIColor(light: 0x1E1A15, dark: 0xF2EBDF)
        let large = UIFont.systemFont(ofSize: 34, weight: .bold, width: .expanded)
        let inline = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline), .foregroundColor: ink]
    }
}
