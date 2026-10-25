import os

/// Journaux de l'appli (Console.app, filtre « com.ovrplow.Semainier ») : les erreurs ne sont plus avalées en silence.
nonisolated enum Journal {
    private static let sous = "com.ovrplow.Semainier"
    /// Base de données : ouverture, lectures, sauvegardes.
    static let donnees = Logger(subsystem: sous, category: "donnees")
    /// Scan et Open Food Facts.
    static let scan = Logger(subsystem: sous, category: "scan")
}
