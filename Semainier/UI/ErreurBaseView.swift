import SwiftUI

/// Écran affiché quand la base ne s'ouvre pas, à la place d'un plantage. Les données restent sur le téléphone tant
/// qu'on ne choisit pas de repartir d'une base vide (l'ancienne est alors mise de côté, pas effacée).
struct ErreurBaseView: View {
    var detail: String
    var reessayer: () -> Void
    var repartir: () -> Void
    @State private var confirme = false

    var body: some View {
        ContentUnavailableView {
            Label("Impossible d'ouvrir les données", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Elles sont toujours sur le téléphone. Réessayer, ou repartir d'une base vide : l'ancienne est mise de côté, et une sauvegarde pourra être importée depuis le menu ⋯.")
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Color.texte3)
                }
            }
        } actions: {
            Button("Réessayer", action: reessayer)
                .buttonStyle(.glassProminent)
            Button("Repartir d'une base vide", role: .destructive) { confirme = true }
        }
        .background(Color.fond)
        .alert("Repartir d'une base vide ?", isPresented: $confirme) {
            Button("Annuler", role: .cancel) {}
            Button("Repartir", role: .destructive, action: repartir)
        } message: {
            Text("L'appli s'ouvrira sans recette ni planning. L'ancienne base reste dans les fichiers de l'appli.")
        }
    }
}
