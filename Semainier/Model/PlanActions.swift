import Foundation
import SwiftData

/// Opérations sur le planning et les données, partagées entre les écrans.
enum PlanActions {
    /// Duplique un plat (portion et quantités modifiées comprises) à la fin d'une case.
    static func duplicate(_ entry: PlanEntry, date: DayKey, slot: Int, in context: ModelContext) {
        guard let copy = entry.copy(to: date, slot: slot, order: nextOrder(date: date, slot: slot, in: context)) else { return }
        context.insert(copy)
    }

    /// Déplace un plat vers un autre jour et/ou repas ; il passe à la fin de la case d'arrivée.
    static func move(_ entry: PlanEntry, date: DayKey, slot: Int, in context: ModelContext) {
        guard entry.date != date || entry.slot != slot else { return }
        entry.order = nextOrder(date: date, slot: slot, in: context)
        entry.date = date
        entry.slot = slot
    }

    static func add(_ recipe: Recipe, date: DayKey, slot: Int, in context: ModelContext) {
        context.insert(PlanEntry(date: date, slot: slot, recipe: recipe, order: nextOrder(date: date, slot: slot, in: context)))
    }

    static func add(_ ingredient: Ingredient, qty: Double, date: DayKey, slot: Int, in context: ModelContext) {
        context.insert(PlanEntry(date: date, slot: slot, ingredient: ingredient, qty: qty,
                                 order: nextOrder(date: date, slot: slot, in: context)))
    }

    private static func nextOrder(date: DayKey, slot: Int, in context: ModelContext) -> Int {
        let d = FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.date == date && $0.slot == slot })
        return ((try? context.fetch(d))?.map(\.order).max() ?? -1) + 1
    }

    /// Passage de la « semaine type » au planning daté : chaque plat est placé à la prochaine
    /// occurrence de son jour (aujourd'hui compris), donc sur les 7 jours à venir.
    static func migrateLegacyDays(in context: ModelContext, today: DayKey = Days.today) {
        let d = FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.date == 0 })
        for e in (try? context.fetch(d)) ?? [] {
            e.date = Days.next(weekday: e.day, from: today)
        }
    }

    /// Ajuste les portions d'un jour pour viser l'objectif. Renvoie false si le jour est vide.
    @discardableResult
    static func fit(_ dayEntries: [PlanEntry], target: Double) -> Bool {
        let kcal = dayEntries.map(\.totals).sum.kcal
        guard let xs = Nutrition.fitted(dayEntries.map(\.x), dayKcal: kcal, target: target) else { return false }
        for (e, x) in zip(dayEntries, xs) { e.x = x }
        return true
    }

    /// Remplace le contenu des jours cibles par celui du jour source.
    static func copy(day source: DayKey, to targets: Set<DayKey>, entries: [PlanEntry], in context: ModelContext) {
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
        return try? context.fetch(d).first
    }

    static func settings(in context: ModelContext) -> AppSettings {
        if let s = try? context.fetch(FetchDescriptor<AppSettings>()).first { return s }
        let s = AppSettings()
        context.insert(s)
        return s
    }
}
