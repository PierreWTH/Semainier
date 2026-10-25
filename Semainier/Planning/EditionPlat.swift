import SwiftData
import SwiftUI

/// Modification d'un plat du planning, depuis la vue Jour ou la grille Semaine : une seule feuille à la fois.
enum EditionPlat: Identifiable {
    /// Nombre de pièces d'un plat qui se compte à la pièce.
    case pieces(PlanEntry)
    case libre(PlanEntry)
    /// Quantité d'un ingrédient seul.
    case quantite(PlanEntry)
    /// Quantité d'une ligne de recette, pour ce plat uniquement.
    case ligne(PlanEntry, RecipeItem)

    struct Cle: Hashable {
        var genre: String
        var plat: PersistentIdentifier
        var ligne: PersistentIdentifier?
    }

    var id: Cle {
        switch self {
        case .pieces(let e): Cle(genre: "pieces", plat: e.persistentModelID)
        case .libre(let e): Cle(genre: "libre", plat: e.persistentModelID)
        case .quantite(let e): Cle(genre: "quantite", plat: e.persistentModelID)
        case .ligne(let e, let it): Cle(genre: "ligne", plat: e.persistentModelID, ligne: it.persistentModelID)
        }
    }
}

private struct EditionPlatSheet: ViewModifier {
    @Binding var edition: EditionPlat?

    func body(content: Content) -> some View {
        content.sheet(item: $edition) { edition in
            switch edition {
            case .pieces(let e):
                if let r = e.recipe {
                    PieceCountSheet(recipe: r, initial: Int(e.x.rounded())) { n in withAnimation(.snappy) { e.x = Double(n) } }
                }
            case .libre(let e):
                FreeMealSheet(initial: e.free) { meal in withAnimation(.snappy) { e.free = meal } }
            case .quantite(let e):
                if let g = e.ingredient {
                    QuantitySheet(ingredient: g, initial: e.qty) { e.qty = $0 }
                }
            case .ligne(let e, let it):
                if let g = it.ingredient {
                    QuantitySheet(ingredient: g, initial: e.qty(for: it) * e.x,
                                  note: "Modifie seulement ce plat du \(Days.longLabel(e.date).lowercased()). La recette n'est pas changée.",
                                  original: it.qty * e.x,
                                  onReset: { withAnimation(.snappy) { e.resetQty(for: it) } }) { q in
                        withAnimation(.snappy) { e.setQty(q, for: it) }
                    }
                }
            }
        }
    }
}

extension View {
    /// Feuille de modification d'un plat (`EditionPlat`).
    func editionPlat(_ edition: Binding<EditionPlat?>) -> some View {
        modifier(EditionPlatSheet(edition: edition))
    }
}
