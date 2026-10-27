import SwiftData
import SwiftUI

/// Modification d'un plat du planning, depuis la vue Jour ou la grille Semaine : une seule feuille à la fois.
enum DishEdit: Identifiable {
    /// Nombre de pièces d'un plat qui se compte à la pièce.
    case pieces(PlanEntry)
    case freeMeal(PlanEntry)
    /// Quantité d'un ingrédient seul.
    case quantity(PlanEntry)
    /// Quantité d'une ligne de recette, pour ce plat uniquement.
    case line(PlanEntry, RecipeItem)

    struct Key: Hashable {
        var kind: String
        var dish: PersistentIdentifier
        var line: PersistentIdentifier?
    }

    var id: Key {
        switch self {
        case .pieces(let e): Key(kind: "pieces", dish: e.persistentModelID)
        case .freeMeal(let e): Key(kind: "libre", dish: e.persistentModelID)
        case .quantity(let e): Key(kind: "quantite", dish: e.persistentModelID)
        case .line(let e, let it): Key(kind: "ligne", dish: e.persistentModelID, line: it.persistentModelID)
        }
    }
}

private struct DishEditSheet: ViewModifier {
    @Binding var dishEdit: DishEdit?

    func body(content: Content) -> some View {
        content.sheet(item: $dishEdit) { dishEdit in
            switch dishEdit {
            case .pieces(let e):
                if let r = e.recipe {
                    PieceCountSheet(recipe: r, initial: Int(e.x.rounded())) { n in withAnimation(.snappy) { e.x = Double(n) } }
                }
            case .freeMeal(let e):
                FreeMealSheet(initial: e.free) { meal in withAnimation(.snappy) { e.free = meal } }
            case .quantity(let e):
                if let g = e.ingredient {
                    QuantitySheet(ingredient: g, initial: e.qty) { e.qty = $0 }
                }
            case .line(let e, let it):
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
    func dishEdit(_ dishEdit: Binding<DishEdit?>) -> some View {
        modifier(DishEditSheet(dishEdit: dishEdit))
    }
}
