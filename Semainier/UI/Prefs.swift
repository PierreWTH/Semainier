import Foundation

/// Clés des préférences (`@AppStorage`, `UserDefaults`), au même endroit. Les scripts (`shots.sh`) et les arguments
/// de lancement des tests utilisent les mêmes.
enum Prefs {
    static let tab = "tab"
    static let planningMode = "planning.mode"
    static let kitchenMode = "cuisine.mode"
    /// Vue Semaine en vue d'ensemble.
    static let overview = "semaine.ensemble"
    /// Plats ou Ingrédients, dans la feuille « Ajouter ».
    static let addMode = "picker.mode"
}

/// Onglets de l'appli.
enum AppTab: String {
    case planning, shopping = "courses", kitchen = "cuisine"
}

/// Vue de l'onglet Planning.
enum PlanningMode: String {
    case week = "semaine", day = "jour"
}

/// Côté affiché dans l'onglet Cuisine.
enum KitchenMode: String {
    case dishes = "plats", ingredients, prep = "preparer"
}

/// Liste affichée dans la feuille « Ajouter » d'un repas.
enum AddMode: String {
    case dishes = "plats", ingredients
}
