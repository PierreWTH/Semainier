import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Jour courant, mis à jour au passage de minuit et au retour de l'appli au premier plan un autre jour :
    /// les vues qui le lisent se redessinent (iOS garde souvent l'appli en mémoire toute la nuit).
    @Entry var currentDay: DayKey = Days.today
}

/// Tient `today` à jour : passage de minuit, retour au premier plan. La vue racine le passe dans `aujourdhui`.
struct DayTracking: ViewModifier {
    @Binding var today: DayKey
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                refresh()
            }
            .onChange(of: scenePhase) { if scenePhase == .active { refresh() } }
    }

    private func refresh() {
        let now = Days.today
        if now != today { today = now }
    }
}
