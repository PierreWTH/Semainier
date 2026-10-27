import SwiftData
import SwiftUI
import UIKit

/// Base de données de l'appli. Si elle ne s'ouvre pas, l'appli affiche `ErreurBaseView` au lieu de s'arrêter :
/// les données restent sur place tant qu'on ne choisit pas de repartir d'une base vide.
@Observable
final class Base {
    private(set) var container: ModelContainer?
    private(set) var settings: AppSettings?
    private(set) var errorMessage: String?
    /// Emplacement du fichier de la base (nil en mémoire).
    private var url: URL?

    init() { openStore() }

    func openStore() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // Stockage local uniquement (compte gratuit). Pour la sync iCloud : cloudKitDatabase: .automatic.
        var config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        #if DEBUG
        // Tests d'interface et mesures : base en mémoire, jamais les vraies données.
        if UITestData.enabled || PerfData.enabled { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true) }
        #endif
        url = config.isStoredInMemoryOnly ? nil : config.url
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: config)
        } catch {
            Journal.store.fault("Ouverture de la base impossible : \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        let context = container.mainContext
        let settings = PlanActions.settings(in: context)
        settings.syncKcalWithMacros()
        PlanActions.migrateLegacyDays(in: context)
        #if DEBUG
        if UITestData.enabled { UITestData.insert(into: context) }
        if PerfData.enabled { PerfData.insert(into: context) }
        #endif
        context.saveOrLog()
        self.container = container
        self.settings = settings
        errorMessage = nil
    }

    /// Met l'ancienne base de côté (renommée, avec ses fichiers annexes) et en ouvre une vide.
    /// On peut ensuite importer une sauvegarde depuis le menu ⋯.
    func startFresh() {
        if let url {
            let fm = FileManager.default
            let suffix = ".illisible-" + Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "")
            for ext in ["", "-wal", "-shm"] {
                let f = URL(fileURLWithPath: url.path + ext)
                guard fm.fileExists(atPath: f.path) else { continue }
                do {
                    try fm.moveItem(at: f, to: URL(fileURLWithPath: f.path + suffix))
                } catch {
                    Journal.store.error("Impossible de mettre de côté \(f.lastPathComponent, privacy: .public) : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        openStore()
    }
}

@main
struct SemainierApp: App {
    @State private var base = Base()
    @State private var toast = Toast()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Tests d'interface : sans animations, un menu contextuel ouvert empêche l'appli d'être « au repos »
        // et chaque action du test attend alors 60 s pour rien.
        if ProcessInfo.processInfo.arguments.contains("-DisableAnimations") { UIView.setAnimationsEnabled(false) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let container = base.container, let settings = base.settings {
                RootView()
                    .environment(settings)
                    .environment(toast)
                    .tint(Color.accentColor)
                    .modelContainer(container)
            } else {
                StoreErrorView(detail: base.errorMessage ?? "", retry: base.openStore, startFresh: base.startFresh)
            }
        }
        // L'enregistrement automatique peut ne pas avoir eu lieu quand iOS suspend l'appli.
        .onChange(of: scenePhase) {
            if scenePhase == .background { base.container?.mainContext.saveOrLog() }
        }
    }
}

struct RootView: View {
    @AppStorage(Prefs.tab) private var tab = AppTab.planning
    @AppStorage(Prefs.kitchenMode) private var kitchenMode = KitchenMode.dishes
    /// Lu ici : un nouveau jour recrée les onglets, et avec eux leurs requêtes sur les prochains jours.
    @State private var today = Days.today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Planning", systemImage: "calendar", value: AppTab.planning) { PlanningView() }
            Tab("Courses", systemImage: "basket", value: AppTab.shopping) { ShoppingView() }
            Tab("Cuisine", systemImage: "frying.pan", value: AppTab.kitchen) { KitchenView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.currentDay, today)
        .modifier(DayTracking(today: $today))
        .modifier(ToastOverlay())
        .onAppear(perform: migrateTab)
    }

    /// Anciens onglets Recettes / Ingrédients (préférence enregistrée, ou écrite par `shots.sh`) :
    /// ouvre l'onglet Cuisine du bon côté. Lus en texte brut : ce ne sont plus des valeurs d'`Onglet`.
    private func migrateTab() {
        switch UserDefaults.standard.string(forKey: Prefs.tab) {
        case "recettes": kitchenMode = .dishes; tab = .kitchen
        case "ingredients": kitchenMode = .ingredients; tab = .kitchen
        default: break
        }
    }
}
