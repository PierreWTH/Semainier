import Foundation

/// Clés des préférences (`@AppStorage`, `UserDefaults`), au même endroit. Les scripts (`shots.sh`) et les arguments
/// de lancement des tests utilisent les mêmes.
enum Prefs {
    static let onglet = "tab"
    static let modePlanning = "planning.mode"
    static let modeCuisine = "cuisine.mode"
    /// Vue Semaine en vue d'ensemble.
    static let ensemble = "semaine.ensemble"
    /// Plats ou Ingrédients, dans la feuille « Ajouter ».
    static let modeAjout = "picker.mode"
}

/// Onglets de l'appli.
enum Onglet: String {
    case planning, courses, cuisine
}

/// Vue de l'onglet Planning.
enum ModePlanning: String {
    case semaine, jour
}

/// Côté affiché dans l'onglet Cuisine.
enum ModeCuisine: String {
    case plats, ingredients, preparer
}

/// Liste affichée dans la feuille « Ajouter » d'un repas.
enum ModeAjout: String {
    case plats, ingredients
}
