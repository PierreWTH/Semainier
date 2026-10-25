import Foundation
import SwiftData
import Testing
@testable import Semainier

/// Les bases créées avant le versionnage du schéma (celle de l'iPhone) doivent s'ouvrir avec `SchemaV1`
/// et `PlanDeMigration`, sans rien perdre.
@MainActor
struct SchemaTests {
    @Test func unversionedStoreOpensWithVersionedSchema() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ancienne-\(UUID()).store")
        defer {
            for ext in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + ext) }
        }

        // Base telle que l'appli la créait avant : schéma simple, sans version ni plan de migration.
        do {
            let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let skyr = Ingredient(name: "Skyr", unit: .g, kcal: 64, p: 11, c: 4, f: 0.2, rayon: .cremerieOeufs)
            context.insert(skyr)
            let r = Recipe(name: "Bol skyr")
            context.insert(r)
            let item = RecipeItem(ingredient: skyr, qty: 200, order: 0)
            context.insert(item)
            item.recipe = r
            let e = PlanEntry(date: 20261026, slot: 2, recipe: r, x: 1.5)
            e.overrides = [skyr.uid: 250]
            context.insert(e)
            context.insert(AppSettings())
            try context.save()
        }

        // Réouverture comme le fait maintenant `Base.ouvrir`.
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(for: schema, migrationPlan: PlanDeMigration.self,
                                           configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<PlanEntry>())
        #expect(entries.count == 1)
        let e = try #require(entries.first)
        #expect(e.recipe?.name == "Bol skyr" && e.x == 1.5 && e.repas == .collation)
        #expect(e.recipe?.items?.first?.ingredient?.name == "Skyr")
        #expect(e.overrides.values.first == 250)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }
}
