//
//  Theme.swift
//  Semainier — direction artistique « Étiquette »
//
//  Tokens de la DA. Les couleurs viennent de Couleurs.xcassets (clair + sombre).
//  Voir DA.md pour l'usage de chaque token, composant par composant.
//

import SwiftUI

// MARK: - Couleurs

extension Color {
    // Fonds et texte
    static let appBackground              = Color("appBackground")
    static let surface           = Color("surface")
    static let surface2          = Color("surface2")
    static let hairline             = Color("hairline")
    static let textPrimary       = Color("textPrimary")
    static let textSecondary            = Color("textSecondary")
    static let textTertiary            = Color("textTertiary")

    // Interaction (AccentColor = bleu émail, à définir comme couleur d'accent du projet)
    static let accentSoft        = Color("accentSoft")
    static let onAccent         = Color("onAccent")

    // Macros — ordre G · P · L partout
    static let carbs              = Color("carbs")
    static let carbsText         = Color("carbsText")
    static let protein              = Color("protein")
    static let proteinText         = Color("proteinText")
    static let fat               = Color("fat")          // barres
    static let fatText          = Color("fatText")     // lettre L, libellé « Lipides »

    // États
    static let overTarget       = Color("overTarget")
    static let ok                = Color("ok")
    static let warning         = Color("warning")

    // Écrans liste et sheets
    static let groupedBackground        = Color("groupedBackground")
    static let groupedSheetBackground   = Color("groupedSheetBackground")

    // Carte de repas (vue Jour)
    static let cardHairline        = Color("cardHairline")   // entre deux lignes d'une carte de repas
    static let expandedBackground        = Color("expandedBackground")   // ingrédients d'un plat déplié

    // Grille Semaine
    static let gridCell        = Color("gridCell")
    static let gridCellBorder = Color("gridCellBorder")
    static let todayColumn     = Color("todayColumn")

    // Repas libre (kcal estimées) : sable et ambre, reconnaissable sans alerter
    static let freeMeal             = Color("freeMeal")          // icône, « ≈ »
    static let freeMealBackground         = Color("freeMealBackground")      // fond de la tuile / de la ligne
    static let freeMealBorder      = Color("freeMealBorder")   // contour de la tuile

    // Carte total (vue Jour)
    static let totalCardTrack   = Color("totalCardTrack")
    static let kcalFill   = Color("kcalFill")
}

enum Macro: CaseIterable {
    case carbs, protein, fat

    var letter: String {
        switch self { case .carbs: "G"; case .protein: "P"; case .fat: "L" }
    }
    var label: String {
        switch self { case .carbs: "Glucides"; case .protein: "Protéines"; case .fat: "Lipides" }
    }
    /// Couleur des barres.
    var barColor: Color {
        switch self { case .carbs: .carbs; case .protein: .protein; case .fat: .fat }
    }
    /// Couleur des lettres et libellés (contraste AA).
    var textColor: Color {
        switch self { case .carbs: .carbsText; case .protein: .proteinText; case .fat: .fatText }
    }
}

// MARK: - Règle de dépassement

/// Couleurs de la règle de dépassement (la règle elle-même est dans `Nutrition`).
enum Threshold {
    /// Au-delà de +3 % de l'objectif, barre et chiffre passent en `depassement`.
    static func exceeds(_ value: Double, target: Double) -> Bool {
        Nutrition.exceeds(value, target: target)
    }

    /// Kcal d'un jour : `ok` dans la cible (±3 %), `depassement` au-delà de +3 %, sinon `sinon`.
    static func dayColor(_ kcal: Double, target: Double, otherwise: Color) -> Color {
        switch Nutrition.dayStatus(kcal: kcal, target: target) {
        case .withinTarget: .ok
        case .aboveTarget: .overTarget
        case .belowTarget: otherwise
        }
    }
}

// MARK: - Espacements et rayons

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let margin: CGFloat = 16   // marge d'écran, padding de carte
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Rayons d'angle (`Rayon` désigne déjà les rayons du magasin).
enum Radius {
    static let dateStamp: CGFloat = 6
    static let chip: CGFloat = 10
    static let dayChip: CGFloat = 12
    static let gridCell: CGFloat = 12
    static let recipeCard: CGFloat = 16
    static let dishCard: CGFloat = 18
    static let totalCardStyle: CGFloat = 20
}

// MARK: - Typographie

/// Styles à taille fixe de la DA, qui suivent quand même la taille de texte dynamique.
enum AppFont {
    case dayTotal        // Rounded 40 Bold
    case weekAverage   // Rounded 22 Bold — moyenne de la semaine
    case headerKcal       // Rounded 14 Semibold — total kcal dans l'en-tête d'un jour (grille)
    case mealBand       // 10,5 Bold, capitales +7 % — bande de repas de la grille
    case cardTotal       // Rounded 28 Bold, −1 % — total du jour dans la carte total
    case cardMacroValue // Rounded 16 Semibold — valeur de macro dans la carte total
    case counter         // Rounded 28 Bold — « 8 / 25 dans le panier »
    case macroValue      // Rounded 22 Semibold — carte total
    case recipeKcal      // Rounded 17 Semibold
    case quantity         // Rounded 16 Semibold — pastille de quantité
    case shoppingQuantity  // Rounded 18 Semibold
    case stripDate      // Rounded 17 Semibold
    case dateStamp       // Rounded 13 Semibold
    case mealHeader      // 13 Semibold, capitales +6 %
    case macroLabel     // 11 Bold, capitales +7 %
    case stripWeekday      // 10 Semibold, capitales

    fileprivate var spec: (size: CGFloat, weight: Font.Weight, design: Font.Design, style: Font.TextStyle, tracking: CGFloat, allCaps: Bool) {
        switch self {
        case .dayTotal:       (40, .bold,     .rounded, .largeTitle,  -0.8, false)
        case .weekAverage:  (22, .bold,     .rounded, .title2,       0,   false)
        case .headerKcal:      (14, .semibold, .rounded, .subheadline,  0,   false)
        case .mealBand:      (10.5, .bold,   .default, .caption2,     0.74, true)
        case .cardTotal:      (28, .bold,     .rounded, .title,       -0.28, false)
        case .cardMacroValue:(16, .semibold, .rounded, .callout,      0,   false)
        case .counter:        (28, .bold,     .rounded, .title,        0,   false)
        case .macroValue:     (22, .semibold, .rounded, .title2,       0,   false)
        case .recipeKcal:     (17, .semibold, .rounded, .headline,     0,   false)
        case .quantity:        (16, .semibold, .rounded, .callout,      0,   false)
        case .shoppingQuantity: (18, .semibold, .rounded, .body,         0,   false)
        case .stripDate:     (17, .semibold, .rounded, .headline,     0,   false)
        case .dateStamp:      (13, .semibold, .rounded, .footnote,     0,   false)
        case .mealHeader:     (13, .semibold, .default, .footnote,     0.8, true)
        case .macroLabel:    (11, .bold,     .default, .caption2,     0.8, true)
        case .stripWeekday:     (10, .semibold, .default, .caption2,     0.5, true)
        }
    }
}

private struct AppFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let appFont: AppFont

    init(_ appFont: AppFont) {
        self.appFont = appFont
        _size = ScaledMetric(wrappedValue: appFont.spec.size, relativeTo: appFont.spec.style)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: appFont.spec.weight, design: appFont.spec.design))
            .tracking(appFont.spec.tracking)
            .textCase(appFont.spec.allCaps ? .uppercase : nil)
            .monospacedDigit()
    }
}

extension View {
    /// Applique un style de la DA. Ex. : `Text("2 360").police(.totalJour)`
    func appFont(_ appFont: AppFont) -> some View { modifier(AppFontModifier(appFont)) }
}

// MARK: - Barres

/// Barre remplie de 0 à 100 % de l'objectif, plafonnée. Au-delà de +3 % : `depassement`.
struct TargetBar: View {
    let value: Double
    let target: Double
    let color: Color
    var track: Color = .surface2
    @ScaledMetric private var height: CGFloat

    init(value: Double, target: Double, color: Color, track: Color = .surface2, height: CGFloat = 6) {
        self.value = value
        self.target = target
        self.color = color
        self.track = track
        _height = ScaledMetric(wrappedValue: height)
    }

    private var ratio: Double { target > 0 ? min(max(value / target, 0), 1) : 0 }
    private var fill: Color { Threshold.exceeds(value, target: target) ? .overTarget : color }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Fmt.n0(value)) sur \(Fmt.n0(target))")
    }
}

/// Répartition G · P · L en kcal (4·G, 4·P, 9·L), segments séparés de 2 pt.
struct SplitBar: View {
    let g: Double, p: Double, l: Double
    var height: CGFloat = 4

    var body: some View {
        let kcal = [g * 4, p * 4, l * 9]
        let total = max(kcal.reduce(0, +), 1)
        GeometryReader { geo in
            let width = geo.size.width - 4
            HStack(spacing: 2) {
                ForEach(Array(Macro.allCases.enumerated()), id: \.offset) { item in
                    Capsule().fill(item.element.barColor).frame(width: width * kcal[item.offset] / total)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Carte total en verre (vue Jour)

extension View {
    /// Carte total : Liquid Glass sans teinte, rayon 20, padding 12 / 16 / 14.
    func totalCardStyle() -> some View {
        padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.totalCardStyle))
    }
}

// MARK: - Tuile de plat (grille Semaine)

extension View {
    /// `libre` : repas libre, sur fond sable avec un contour sable.
    func gridTile(freeMeal: Bool = false) -> some View {
        padding(EdgeInsets(top: 8, leading: 9, bottom: 9, trailing: 9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridCard(fill: freeMeal ? .freeMealBackground : .gridCell, border: freeMeal ? .freeMealBorder : .gridCellBorder)
    }

    /// Fond, contour et ombre d'une tuile, sans marge intérieure. Le contenu est rogné aux coins :
    /// une carte qui s'agrandit se déroule vers le bas, depuis l'intérieur de la carte.
    func gridCard(fill: Color = .gridCell, border: Color = .gridCellBorder) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(.rect(cornerRadius: Radius.gridCell))
            .overlay(RoundedRectangle(cornerRadius: Radius.gridCell).strokeBorder(border, lineWidth: 1))
            .modifier(LightModeShadow())
    }
}

private struct LightModeShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.shadow(color: scheme == .light ? Color(red: 40/255, green: 32/255, blue: 16/255).opacity(0.12) : .clear,
                       radius: 1.5, y: 1)
    }
}

// MARK: - Fond commun

extension View {
    /// Fond unique de l'appli (celui du Planning), y compris derrière les listes et formulaires.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.appBackground)
    }
}
