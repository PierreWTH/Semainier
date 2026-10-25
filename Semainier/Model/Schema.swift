import Foundation
import SwiftData

/// Version 1 du modèle, celle en place avant le versionnage : identique aux classes de `Models.swift`.
/// Pour faire évoluer le modèle, ajouter une `SchemaV2` (avec ses classes), puis une étape dans `PlanDeMigration`,
/// sans toucher à celle-ci : c'est ce qui permet d'ouvrir les bases existantes.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self]
    }
}

nonisolated enum PlanDeMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
