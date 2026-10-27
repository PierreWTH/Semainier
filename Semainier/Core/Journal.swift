import os

/// Journaux de l'appli (Console.app, filtre « com.ovrplow.Semainier ») : les erreurs ne sont plus avalées en silence.
nonisolated enum Journal {
    private static let belowColor = "com.ovrplow.Semainier"
    /// Base de données : ouverture, lectures, sauvegardes.
    static let store = Logger(subsystem: belowColor, category: "donnees")
    /// Scan et Open Food Facts.
    static let scan = Logger(subsystem: belowColor, category: "scan")
}
