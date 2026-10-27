import SwiftUI

/// Écran affiché quand la base ne s'ouvre pas, à la place d'un plantage. Les données restent sur le téléphone tant
/// qu'on ne choisit pas de repartir d'une base vide (l'ancienne est alors mise de côté, pas effacée).
struct StoreErrorView: View {
    var detail: String
    var retry: () -> Void
    var startFresh: () -> Void
    @State private var confirming = false

    var body: some View {
        ContentUnavailableView {
            Label("Impossible d'ouvrir les données", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Elles sont toujours sur le téléphone. Réessayer, ou repartir d'une base vide : l'ancienne est mise de côté, et une sauvegarde pourra être importée depuis le menu ⋯.")
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Color.textTertiary)
                }
            }
        } actions: {
            Button("Réessayer", action: retry)
                .buttonStyle(.glassProminent)
            Button("Repartir d'une base vide", role: .destructive) { confirming = true }
        }
        .background(Color.appBackground)
        .alert("Repartir d'une base vide ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Repartir", role: .destructive, action: startFresh)
        } message: {
            Text("L'appli s'ouvrira sans recette ni planning. L'ancienne base reste dans les fichiers de l'appli.")
        }
    }
}
