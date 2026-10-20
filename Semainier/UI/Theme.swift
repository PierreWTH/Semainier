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
    static let fond              = Color("fond")
    static let surface           = Color("surface")
    static let surface2          = Color("surface2")
    static let filet             = Color("filet")
    static let texte             = Color("texte")
    static let texte2            = Color("texte2")
    static let texte3            = Color("texte3")

    // Interaction (AccentColor = bleu émail, à définir comme couleur d'accent du projet)
    static let accentDoux        = Color("accentDoux")
    static let surAccent         = Color("surAccent")

    // Macros — ordre G · P · L partout
    static let gluc              = Color("gluc")
    static let glucTexte         = Color("glucTexte")
    static let prot              = Color("prot")
    static let protTexte         = Color("protTexte")
    static let lip               = Color("lip")          // barres
    static let lipTexte          = Color("lipTexte")     // lettre L, libellé « Lipides »

    // États
    static let depassement       = Color("depassement")
    static let ok                = Color("ok")
    static let attention         = Color("attention")

    // Écrans liste et sheets
    static let fondGroupe        = Color("fondGroupe")
    static let fondGroupeSheet   = Color("fondGroupeSheet")

    // Carte de repas (vue Jour)
    static let filetCarte        = Color("filetCarte")   // entre deux lignes d'une carte de repas
    static let fondDeplie        = Color("fondDeplie")   // ingrédients d'un plat déplié

    // Grille Semaine
    static let caseGrille        = Color("caseGrille")
    static let caseGrilleContour = Color("caseGrilleContour")
    static let colonneDuJour     = Color("colonneDuJour")

    // Repas libre (kcal estimées) : sable et ambre, reconnaissable sans alerter
    static let libre             = Color("libre")          // icône, « ≈ »
    static let libreFond         = Color("libreFond")      // fond de la tuile / de la ligne
    static let libreContour      = Color("libreContour")   // contour de la tuile

    // Carte total (vue Jour)
    static let pisteCarteTotal   = Color("pisteCarteTotal")
    static let remplissageKcal   = Color("remplissageKcal")
}

enum Macro: CaseIterable {
    case glucides, proteines, lipides

    var lettre: String {
        switch self { case .glucides: "G"; case .proteines: "P"; case .lipides: "L" }
    }
    var libelle: String {
        switch self { case .glucides: "Glucides"; case .proteines: "Protéines"; case .lipides: "Lipides" }
    }
    /// Couleur des barres.
    var trait: Color {
        switch self { case .glucides: .gluc; case .proteines: .prot; case .lipides: .lip }
    }
    /// Couleur des lettres et libellés (contraste AA).
    var texte: Color {
        switch self { case .glucides: .glucTexte; case .proteines: .protTexte; case .lipides: .lipTexte }
    }
}

// MARK: - Règle de dépassement

/// Couleurs de la règle de dépassement (la règle elle-même est dans `Nutrition`).
enum Seuil {
    /// Au-delà de +3 % de l'objectif, barre et chiffre passent en `depassement`.
    static func depasse(_ valeur: Double, objectif: Double) -> Bool {
        Nutrition.depasse(valeur, objectif: objectif)
    }

    /// Kcal d'un jour : `ok` dans la cible (±3 %), `depassement` au-delà de +3 %, sinon `sinon`.
    static func couleurJour(_ kcal: Double, objectif: Double, sinon: Color) -> Color {
        switch Nutrition.etatJour(kcal: kcal, objectif: objectif) {
        case .dansLaCible: .ok
        case .auDela: .depassement
        case .sousObjectif: sinon
        }
    }
}

// MARK: - Espacements et rayons

enum Espace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let marge: CGFloat = 16   // marge d'écran, padding de carte
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Rayons d'angle (`Rayon` désigne déjà les rayons du magasin).
enum Arrondi {
    static let tamponDate: CGFloat = 6
    static let pastille: CGFloat = 10
    static let puceJour: CGFloat = 12
    static let caseGrille: CGFloat = 12
    static let carteRecette: CGFloat = 16
    static let cartePlat: CGFloat = 18
    static let carteTotal: CGFloat = 20
}

// MARK: - Typographie

/// Styles à taille fixe de la DA, qui suivent quand même la taille de texte dynamique.
enum Police {
    case totalJour        // Rounded 40 Bold
    case moyenneSemaine   // Rounded 22 Bold — moyenne de la semaine
    case kcalEnTete       // Rounded 14 Semibold — total kcal dans l'en-tête d'un jour (grille)
    case bandeRepas       // 10,5 Bold, capitales +7 % — bande de repas de la grille
    case totalCarte       // Rounded 28 Bold, −1 % — total du jour dans la carte total
    case valeurMacroCarte // Rounded 16 Semibold — valeur de macro dans la carte total
    case compteur         // Rounded 28 Bold — « 8 / 25 dans le panier »
    case valeurMacro      // Rounded 22 Semibold — carte total
    case kcalRecette      // Rounded 17 Semibold
    case quantite         // Rounded 16 Semibold — pastille de quantité
    case quantiteCourses  // Rounded 18 Semibold
    case dateBandeau      // Rounded 17 Semibold
    case tamponDate       // Rounded 13 Semibold
    case enTeteRepas      // 13 Semibold, capitales +6 %
    case libelleMacro     // 11 Bold, capitales +7 %
    case jourBandeau      // 10 Semibold, capitales

    fileprivate var spec: (size: CGFloat, weight: Font.Weight, design: Font.Design, style: Font.TextStyle, tracking: CGFloat, majuscules: Bool) {
        switch self {
        case .totalJour:       (40, .bold,     .rounded, .largeTitle,  -0.8, false)
        case .moyenneSemaine:  (22, .bold,     .rounded, .title2,       0,   false)
        case .kcalEnTete:      (14, .semibold, .rounded, .subheadline,  0,   false)
        case .bandeRepas:      (10.5, .bold,   .default, .caption2,     0.74, true)
        case .totalCarte:      (28, .bold,     .rounded, .title,       -0.28, false)
        case .valeurMacroCarte:(16, .semibold, .rounded, .callout,      0,   false)
        case .compteur:        (28, .bold,     .rounded, .title,        0,   false)
        case .valeurMacro:     (22, .semibold, .rounded, .title2,       0,   false)
        case .kcalRecette:     (17, .semibold, .rounded, .headline,     0,   false)
        case .quantite:        (16, .semibold, .rounded, .callout,      0,   false)
        case .quantiteCourses: (18, .semibold, .rounded, .body,         0,   false)
        case .dateBandeau:     (17, .semibold, .rounded, .headline,     0,   false)
        case .tamponDate:      (13, .semibold, .rounded, .footnote,     0,   false)
        case .enTeteRepas:     (13, .semibold, .default, .footnote,     0.8, true)
        case .libelleMacro:    (11, .bold,     .default, .caption2,     0.8, true)
        case .jourBandeau:     (10, .semibold, .default, .caption2,     0.5, true)
        }
    }
}

private struct PoliceModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let police: Police

    init(_ police: Police) {
        self.police = police
        _size = ScaledMetric(wrappedValue: police.spec.size, relativeTo: police.spec.style)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: police.spec.weight, design: police.spec.design))
            .tracking(police.spec.tracking)
            .textCase(police.spec.majuscules ? .uppercase : nil)
            .monospacedDigit()
    }
}

extension View {
    /// Applique un style de la DA. Ex. : `Text("2 360").police(.totalJour)`
    func police(_ police: Police) -> some View { modifier(PoliceModifier(police)) }
}

// MARK: - Barres

/// Barre remplie de 0 à 100 % de l'objectif, plafonnée. Au-delà de +3 % : `depassement`.
struct BarreObjectif: View {
    let valeur: Double
    let objectif: Double
    let couleur: Color
    var piste: Color = .surface2
    @ScaledMetric private var hauteur: CGFloat

    init(valeur: Double, objectif: Double, couleur: Color, piste: Color = .surface2, hauteur: CGFloat = 6) {
        self.valeur = valeur
        self.objectif = objectif
        self.couleur = couleur
        self.piste = piste
        _hauteur = ScaledMetric(wrappedValue: hauteur)
    }

    private var ratio: Double { objectif > 0 ? min(max(valeur / objectif, 0), 1) : 0 }
    private var remplissage: Color { Seuil.depasse(valeur, objectif: objectif) ? .depassement : couleur }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(piste)
                Capsule().fill(remplissage).frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: hauteur)
        .accessibilityElement()
        .accessibilityValue("\(Fmt.n0(valeur)) sur \(Fmt.n0(objectif))")
    }
}

/// Répartition G · P · L en kcal (4·G, 4·P, 9·L), segments séparés de 2 pt.
struct BarreRepartition: View {
    let g: Double, p: Double, l: Double
    var hauteur: CGFloat = 4

    var body: some View {
        let kcal = [g * 4, p * 4, l * 9]
        let total = max(kcal.reduce(0, +), 1)
        GeometryReader { geo in
            let largeur = geo.size.width - 4
            HStack(spacing: 2) {
                ForEach(Array(Macro.allCases.enumerated()), id: \.offset) { item in
                    Capsule().fill(item.element.trait).frame(width: largeur * kcal[item.offset] / total)
                }
            }
        }
        .frame(height: hauteur)
        .accessibilityHidden(true)
    }
}

// MARK: - Carte total en verre (vue Jour)

extension View {
    /// Carte total : Liquid Glass sans teinte, rayon 20, padding 12 / 16 / 14.
    func carteTotal() -> some View {
        padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
            .glassEffect(.regular, in: .rect(cornerRadius: Arrondi.carteTotal))
    }
}

// MARK: - Tuile de plat (grille Semaine)

extension View {
    /// `libre` : repas libre, sur fond sable avec un contour sable.
    func tuileGrille(libre: Bool = false) -> some View {
        padding(EdgeInsets(top: 8, leading: 9, bottom: 9, trailing: 9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .carteGrille(fond: libre ? .libreFond : .caseGrille, contour: libre ? .libreContour : .caseGrilleContour)
    }

    /// Fond, contour et ombre d'une tuile, sans marge intérieure. Le contenu est rogné aux coins :
    /// une carte qui s'agrandit se déroule vers le bas, depuis l'intérieur de la carte.
    func carteGrille(fond: Color = .caseGrille, contour: Color = .caseGrilleContour) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(fond)
            .clipShape(.rect(cornerRadius: Arrondi.caseGrille))
            .overlay(RoundedRectangle(cornerRadius: Arrondi.caseGrille).strokeBorder(contour, lineWidth: 1))
            .modifier(OmbreClaireUniquement())
    }
}

private struct OmbreClaireUniquement: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.shadow(color: scheme == .light ? Color(red: 40/255, green: 32/255, blue: 16/255).opacity(0.12) : .clear,
                       radius: 1.5, y: 1)
    }
}

// MARK: - Fond commun

extension View {
    /// Fond unique de l'appli (celui du Planning), y compris derrière les listes et formulaires.
    func fondEcran() -> some View {
        scrollContentBackground(.hidden).background(Color.fond)
    }
}
