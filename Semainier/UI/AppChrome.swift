import SwiftData
import SwiftUI

/// Barre d'outils commune à chaque onglet : menu (objectifs, réglages, sauvegarde).
/// `extra` : entrées propres à l'écran, affichées en tête du menu.
/// `dayTotals` : bulle du total du jour (vue Jour, quand sa carte total est sortie de l'écran).
struct AppChrome<Extra: View>: ViewModifier {
    var dayTotals: Macros?
    var extra: Extra

    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Environment(\.modelContext) private var context

    @State private var editingTargets = false
    @State private var editingSettings = false
    @State private var exportFile: BackupFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: Backup?
    @State private var importError: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let t = dayTotals {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { editingTargets = true } label: { bubble(t) }
                            .accessibilityLabel("Total du jour : \(Fmt.n0(t.kcal)) sur \(Fmt.n0(settings.targetKcal)) kilocalories")
                            .accessibilityHint("Modifier mes objectifs")
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Plus", systemImage: "ellipsis") {
                        Section { extra }
                        Button("Mes objectifs", systemImage: "target") { editingTargets = true }
                        Button("Réglages", systemImage: "gearshape") { editingSettings = true }
                        Divider()
                        Button("Exporter les données", systemImage: "square.and.arrow.up") { export() }
                        Button("Importer une sauvegarde", systemImage: "square.and.arrow.down") { importing = true }
                    }
                }
            }
            .sheet(isPresented: $editingTargets) { TargetsSheet() }
            .sheet(isPresented: $editingSettings) { SettingsSheet() }
            .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json,
                          defaultFilename: "semainier-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
                if case .success = result { toast.show("Sauvegarde exportée") }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                readImport(result)
            }
            .alert("Remplacer toutes les données ?", isPresented: Binding(
                get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }
            )) {
                Button("Annuler", role: .cancel) {}
                Button("Remplacer", role: .destructive) { applyImport() }
            } message: {
                if let b = pendingImport {
                    Text("\(b.ingredients.count) ingrédients, \(b.recipes.count) recettes et \(b.plan.count) plats au planning. Les données actuelles seront effacées.")
                }
            }
            .alert("Import impossible", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") {}
            } message: {
                Text(importError ?? "")
            }
    }

    /// Total du jour, en `ok` / `depassement` selon la cible, en accent sinon.
    private func bubble(_ m: Macros) -> some View {
        let color = Threshold.dayColor(m.kcal, target: settings.targetKcal, otherwise: .accentColor)
        return VStack(alignment: .trailing, spacing: 0) {
            Text("\(Fmt.n0(m.kcal)) kcal")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: m.kcal))
            MacroLine(m: m, unit: " g").font(.system(size: 11)).foregroundStyle(Color.textSecondary)
        }
        .monospacedDigit()
        .padding(.horizontal, 6)
        .animation(.snappy, value: m.kcal)
    }

    private func export() {
        do {
            try context.save()
            exportFile = try BackupFile(Backup.make(from: context))
            exporting = true
        } catch {
            importError = "Export impossible : \(error.localizedDescription)"
        }
    }

    private func readImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url))
        } catch {
            importError = "Ce fichier n'est pas une sauvegarde Semainier lisible."
        }
    }

    private func applyImport() {
        guard let b = pendingImport else { return }
        pendingImport = nil
        do {
            try b.restore(into: context)
            toast.show("Sauvegarde importée")
        } catch {
            importError = error.localizedDescription
        }
    }
}

extension View {
    func appChrome() -> some View { modifier(AppChrome(extra: EmptyView())) }

    func appChrome<Extra: View>(dayTotals: Macros? = nil, @ViewBuilder menu: () -> Extra) -> some View {
        modifier(AppChrome(dayTotals: dayTotals, extra: menu()))
    }
}

struct TargetsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        LabeledContent("Kcal") {
                            Text(Fmt.n0(kcal)).font(.body.bold()).monospacedDigit()
                                .contentTransition(.numericText(value: kcal))
                                .animation(.snappy, value: kcal)
                        }
                        NumberField(label: "Glucides (g)", text: $c, color: Color.carbsText)
                        NumberField(label: "Protéines (g)", text: $p, color: Color.proteinText)
                        NumberField(label: "Lipides (g)", text: $f, color: Color.fatText)
                    } footer: {
                        Text(hint)
                    }
                }
                .listRowBackground(Color.surface)
            }
            .screenBackground()
            .navigationTitle("Mes objectifs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", role: .confirm) {
                        settings.targets = Macros(kcal: kcal, p: Fmt.parse(p) ?? 0, c: Fmt.parse(c) ?? 0, f: Fmt.parse(f) ?? 0)
                        toast.show("Objectifs enregistrés")
                        dismiss()
                    }
                    .disabled(kcal <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.appBackground)
        .onAppear {
            p = Fmt.input(settings.targetP)
            c = Fmt.input(settings.targetC)
            f = Fmt.input(settings.targetF)
        }
    }

    /// Objectif kcal déduit des macros : 4 × G + 4 × P + 9 × L.
    private var kcal: Double {
        Macros(p: Fmt.parse(p) ?? 0, c: Fmt.parse(c) ?? 0, f: Fmt.parse(f) ?? 0).kcalFromMacros
    }

    private var hint: String {
        let pv = Fmt.parse(p) ?? 0, cv = Fmt.parse(c) ?? 0, fv = Fmt.parse(f) ?? 0
        let m = kcal
        guard m > 0 else { return "Par jour. Les kcal sont calculées à partir des macros (4 × G + 4 × P + 9 × L)." }
        return "Calculé à partir des macros (4 × G + 4 × P + 9 × L). Répartition : G \(Fmt.n0(cv * 4 / m * 100)) % · P \(Fmt.n0(pv * 4 / m * 100)) % · L \(Fmt.n0(fv * 9 / m * 100)) %."
    }
}

/// Ligne de formulaire avec un champ numérique aligné à droite.
struct NumberField: View {
    var label: String
    @Binding var text: String
    var color: Color = .primary
    var placeholder = "0"
    /// Valeur signalée (ex. kcal incohérentes) : en Semibold dans cette couleur, avec un triangle.
    var valueColor: Color? = nil

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                if let valueColor {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(valueColor)
                        .accessibilityLabel("Incohérent avec les macros")
                }
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fontWeight(valueColor == nil ? nil : .semibold)
                    .foregroundStyle(valueColor ?? .primary)
            }
        } label: {
            Text(label).foregroundStyle(color)
        }
    }
}
