import Foundation
import SwiftData

/// Opérations sur le planning et les données, partagées entre les écrans.
enum PlanActions {
    /// Duplique un plat (portion et quantités modifiées comprises) à la fin d'une case.
    static func duplicate(_ entry: PlanEntry, date: DayKey, slot: Repas, in context: ModelContext) {
        guard let copy = entry.copy(to: date, repas: slot, order: nextOrder(date: date, slot: slot, in: context)) else { return }
        context.insert(copy)
    }

    /// Déplace un plat vers un autre jour et/ou repas ; il passe à la fin de la case d'arrivée.
    static func move(_ entry: PlanEntry, date: DayKey, slot: Repas, in context: ModelContext) {
        guard entry.date != date || entry.repas != slot else { return }
        entry.order = nextOrder(date: date, slot: slot, in: context)
        entry.date = date
        entry.repas = slot
    }

    /// `x` : portion, ou nombre de pièces pour une recette qui se compte à la pièce.
    static func add(_ recipe: Recipe, x: Double = 1, date: DayKey, slot: Repas, in context: ModelContext) {
        context.insert(PlanEntry(date: date, slot: slot.rawValue, recipe: recipe, x: x, order: nextOrder(date: date, slot: slot, in: context)))
    }

    static func add(_ ingredient: Ingredient, qty: Double, date: DayKey, slot: Repas, in context: ModelContext) {
        context.insert(PlanEntry(date: date, slot: slot.rawValue, ingredient: ingredient, qty: qty,
                                 order: nextOrder(date: date, slot: slot, in: context)))
    }

    static func add(_ free: FreeMeal, date: DayKey, slot: Repas, in context: ModelContext) {
        context.insert(PlanEntry(date: date, slot: slot.rawValue, free: free, order: nextOrder(date: date, slot: slot, in: context)))
    }

    /// Ingrédients seuls enregistrés comme recette : ils laissent place à un seul plat de cette recette,
    /// au rang du premier d'entre eux.
    static func replace(_ entries: [PlanEntry], with recipe: Recipe, in context: ModelContext) {
        guard let first = entries.min(by: { $0.order < $1.order }) else { return }
        context.insert(PlanEntry(date: first.date, slot: first.slot, recipe: recipe, order: first.order))
        entries.forEach(context.delete)
    }

    private static func nextOrder(date: DayKey, slot: Repas, in context: ModelContext) -> Int {
        let slot = slot.rawValue
        let d = FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.date == date && $0.slot == slot })
        return (context.lire(d).map(\.order).max() ?? -1) + 1
    }

    /// Passage de la « semaine type » au planning daté : chaque plat est placé à la prochaine
    /// occurrence de son jour (aujourd'hui compris), donc sur les 7 jours à venir.
    static func migrateLegacyDays(in context: ModelContext, today: DayKey = Days.today) {
        let d = FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.date == 0 })
        for e in context.lire(d) {
            e.date = Days.next(weekday: e.day, from: today)
        }
    }

    /// Remplace le contenu des jours cibles par celui du jour source.
    static func copy(day source: DayKey, to targets: Set<DayKey>, in context: ModelContext) {
        let days = Array(targets) + [source]
        let entries = context.lire(FetchDescriptor<PlanEntry>(predicate: #Predicate { days.contains($0.date) }))
        let model = entries.on(source)
        for d in targets where d != source {
            entries.filter { $0.date == d }.forEach(context.delete)
            for e in model {
                if let copy = e.copy(to: d) { context.insert(copy) }
            }
        }
    }

    /// Supprime un ingrédient : il disparaît aussi des recettes et de la liste de courses.
    static func delete(_ ing: Ingredient, settings: AppSettings, in context: ModelContext) {
        settings.checked.removeAll { $0 == ing.uid }
        context.delete(ing)
    }

    static func ingredient(barcode: String, in context: ModelContext) -> Ingredient? {
        let d = FetchDescriptor<Ingredient>(predicate: #Predicate { $0.barcode == barcode })
        return context.lire(d).first
    }

    static func settings(in context: ModelContext) -> AppSettings {
        if let s = context.lire(FetchDescriptor<AppSettings>()).first { return s }
        let s = AppSettings()
        context.insert(s)
        return s
    }
}
