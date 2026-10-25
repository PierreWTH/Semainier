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
    /// Code lu, traité quand la caméra a fini de se fermer.
    @State private var scanned: String?
    /// Ingrédient enregistré, rendu à `onIngredient` quand la fiche a fini de se fermer.
    @State private var saved: Ingredient?
    /// « Rescanner » : la caméra rouvre quand la fiche a fini de se fermer.
    @State private var rescan = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented, onDismiss: {
                guard let code = scanned else { return }
                scanned = nil
                Task { await handle(code) }
            }) {
                BarcodeScannerView { code in
                    scanned = code
                    isPresented = false
                }
            }
            .sheet(item: $editing, onDismiss: {
                if let i = saved { saved = nil; onIngredient?(i) }
                if rescan { rescan = false; isPresented = true }
            }) { t in
                IngredientEditor(target: t, onSaved: { saved = $0 }, onRescan: {
                    rescan = true
                    editing = nil
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

    /// Appelé une fois la caméra fermée.
    private func handle(_ code: String) async {
        if let existing = PlanActions.ingredient(barcode: code, in: context) {
            if pickExisting, let onIngredient {
                onIngredient(existing)
            } else {
                editing = IngredientEditTarget(ingredient: existing, note: "Déjà dans les ingrédients.")
            }
            return
        }

        searching = true
        defer { searching = false }
        do {
            if let product = try await OpenFoodFacts.lookup(code) {
                let draft = IngredientDraft(scanned: product, barcode: code)
                editing = IngredientEditTarget(draft: draft,
                                               note: "Trouvé sur Open Food Facts. Vérifier les valeurs avant d'enregistrer.",
                                               scan: ScanContext(code: code, initial: draft,
                                                                 terms: product.name.replacingOccurrences(of: " · ", with: " ")))
            } else {
                let draft = IngredientDraft(barcode: code)
                editing = IngredientEditTarget(draft: draft,
                                               note: "Produit introuvable sur Open Food Facts. Recopier les valeurs de l'étiquette.",
                                               scan: ScanContext(code: code, initial: draft, terms: ""))
            }
        } catch {
            let draft = IngredientDraft(barcode: code)
            editing = IngredientEditTarget(draft: draft,
                                           note: "Pas de connexion. Recopier les valeurs de l'étiquette.",
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
