import SwiftData
import SwiftUI

/// Scan → ingrédient existant, ou fiche préremplie depuis Open Food Facts.
struct ScanFlow: ViewModifier {
    @Binding var isPresented: Bool
    /// Si le code est déjà connu : le choisir directement (sélecteur de recette) plutôt que l'ouvrir.
    var pickExisting: Bool
    var onIngredient: ((Ingredient) -> Void)?

    @Environment(\.modelContext) private var context
    @State private var editing: IngredientEditTarget?
    @State private var searching = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                BarcodeScannerView { code in
                    isPresented = false
                    Task { await handle(code) }
                }
            }
            .sheet(item: $editing) { t in
                IngredientEditor(target: t, onSaved: onIngredient, onRescan: {
                    editing = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        isPresented = true
                    }
                })
            }
            .overlay {
                if searching {
                    ProgressView("Recherche du produit…")
                        .padding(20)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
    }

    private func handle(_ code: String) async {
        // Laisse la caméra se fermer avant d'ouvrir la fiche.
        try? await Task.sleep(for: .milliseconds(450))

        if let existing = PlanActions.ingredient(barcode: code, in: context) {
            if pickExisting, let onIngredient {
                onIngredient(existing)
            } else {
                editing = IngredientEditTarget(ingredient: existing, note: "Déjà dans tes ingrédients.")
            }
            return
        }

        searching = true
        defer { searching = false }
        do {
            if let product = try await OpenFoodFacts.lookup(code) {
                let draft = IngredientDraft(scanned: product, barcode: code)
                editing = IngredientEditTarget(draft: draft,
                                               note: "Trouvé sur Open Food Facts. Vérifie les valeurs avant d'enregistrer.",
                                               scan: ScanContext(code: code, initial: draft,
                                                                 terms: product.name.replacingOccurrences(of: " · ", with: " ")))
            } else {
                let draft = IngredientDraft(barcode: code)
                editing = IngredientEditTarget(draft: draft,
                                               note: "Produit introuvable sur Open Food Facts. Recopie les valeurs de l'étiquette.",
                                               scan: ScanContext(code: code, initial: draft, terms: ""))
            }
        } catch {
            let draft = IngredientDraft(barcode: code)
            editing = IngredientEditTarget(draft: draft,
                                           note: "Pas de connexion. Recopie les valeurs de l'étiquette.",
                                           scan: ScanContext(code: code, initial: draft, terms: ""))
        }
    }
}

extension View {
    func barcodeScanFlow(isPresented: Binding<Bool>, pickExisting: Bool = false,
                         onIngredient: ((Ingredient) -> Void)? = nil) -> some View {
        modifier(ScanFlow(isPresented: isPresented, pickExisting: pickExisting, onIngredient: onIngredient))
    }
}
