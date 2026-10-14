import SwiftData
import SwiftUI

@main
struct SemainierApp: App {
    let container: ModelContainer
    let settings: AppSettings
    @State private var toast = Toast()

    init() {
        let schema = Schema([Ingredient.self, Recipe.self, RecipeItem.self, PlanEntry.self, AppSettings.self])
        // Stockage local uniquement (compte gratuit). Pour la sync iCloud : cloudKitDatabase: .automatic.
        var config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        #if DEBUG
        // Tests d'interface : base en mémoire, jamais les vraies données.
        if UITestData.enabled { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true) }
        #endif
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Impossible d'ouvrir la base : \(error)")
        }
        settings = PlanActions.settings(in: container.mainContext)
        settings.syncKcalWithMacros()
        PlanActions.migrateLegacyDays(in: container.mainContext)
        #if DEBUG
        if UITestData.enabled { UITestData.insert(into: container.mainContext) }
        #endif
        try? container.mainContext.save()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(toast)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @AppStorage("tab") private var tab = "planning"

    var body: some View {
        TabView(selection: $tab) {
            Tab("Planning", systemImage: "calendar", value: "planning") { PlanningView() }
            Tab("Courses", systemImage: "basket", value: "courses") { ShoppingView() }
            Tab("Recettes", systemImage: "fork.knife", value: "recettes") { RecipesView() }
            Tab("Ingrédients", systemImage: "leaf", value: "ingredients") { IngredientsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(ToastOverlay())
    }
}
