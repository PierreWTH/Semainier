import SwiftUI

/// Réglages de l'appli. Chaque changement s'applique tout de suite.
struct SettingsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Group {
                    Section {
                        Toggle("Semaine du lundi au dimanche", isOn: $settings.weekFromMonday.animation(.snappy))
                    } header: {
                        Text("Planning")
                    } footer: {
                        Text(settings.weekFromMonday
                             ? "La vue Semaine montre la semaine en cours, du lundi au dimanche."
                             : "La vue Semaine montre les 7 jours à partir d'aujourd'hui.")
                    }
                    // Mentions exigées par les licences (CC-BY 4.0 pour Ciqual, ODbL pour Open Food Facts).
                    Section {
                        Link(destination: URL(string: "https://ciqual.anses.fr")!) {
                            LabeledContent("Aliments bruts", value: FoodLibrary.source)
                        }
                        Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                            LabeledContent("Produits scannés", value: "Open Food Facts")
                        }
                    } header: {
                        Text("Sources des données")
                    } footer: {
                        Text("Table de composition nutritionnelle Ciqual 2025 de l'Anses, sous licence [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.fr) : sélection d'aliments bruts, noms simplifiés et variétés proches regroupées par Semainier. Open Food Facts, sous licence [ODbL](https://opendatacommons.org/licenses/odbl/1-0/).")
                    }
                }
                .listRowBackground(Color.surface)
            }
            .screenBackground()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.appBackground)
    }
}
