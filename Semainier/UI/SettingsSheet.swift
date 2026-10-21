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
                }
                .listRowBackground(Color.surface)
            }
            .fondEcran()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.fond)
    }
}
