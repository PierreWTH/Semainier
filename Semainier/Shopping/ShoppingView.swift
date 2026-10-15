import SwiftData
import SwiftUI
import UIKit

struct ShoppingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Query private var entries: [PlanEntry]

    struct Line: Identifiable {
        var ingredient: Ingredient
        var qty: Double
        var id: PersistentIdentifier { ingredient.persistentModelID }
        var text: String { Fmt.shop(qty, unit: ingredient.unit) }
    }

    /// Somme de qty × x par ingrédient sur les jours sélectionnés.
    private var lines: [Line] {
        // shopDays : décalages à partir d'aujourd'hui (0 = aujourd'hui … 6).
        let days = Set(settings.shopDays.map { Days.adding($0, to: Days.today) })
        var byID: [PersistentIdentifier: Ingredient] = [:]
        var raw: [(key: PersistentIdentifier, qty: Double)] = []
        for e in entries where days.contains(e.date) {
            for (g, q) in e.shoppingLines {
                byID[g.persistentModelID] = g
                raw.append((g.persistentModelID, q))
            }
        }
        return Nutrition.aggregate(raw).compactMap { id, q in
            guard q > 0, let g = byID[id] else { return nil }
            return Line(ingredient: g, qty: q)
        }
    }

    private func isChecked(_ g: Ingredient) -> Bool { settings.checked.contains(g.uid) }

    private func sorted(_ items: [Line]) -> [Line] {
        items.sorted {
            let a = isChecked($0.ingredient), b = isChecked($1.ingredient)
            if a != b { return !a }
            return $0.ingredient.name.localizedStandardCompare($1.ingredient.name) == .orderedAscending
        }
    }

    var body: some View {
        let all = lines
        let done = all.filter { isChecked($0.ingredient) }.count

        NavigationStack {
            List {
                Section {
                    dayPicker
                } footer: {
                    Text("Total des ingrédients pour les jours choisis, portions ajustées comprises.")
                }

                if all.isEmpty {
                    ContentUnavailableView("Rien à acheter pour l'instant", systemImage: "basket",
                                           description: Text("Place des plats dans ton planning, la liste se remplit toute seule."))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        HStack {
                            Text("\(Text("\(done)").bold()) / \(all.count) dans le panier").monospacedDigit()
                            Spacer()
                            Button("Tout décocher") { withAnimation { settings.checked = [] } }
                                .buttonStyle(.borderless)
                                .disabled(done == 0)
                        }
                    }
                    ForEach(Rayon.allCases) { rayon in
                        let items = all.filter { $0.ingredient.rayon == rayon }
                        if !items.isEmpty {
                            Section(rayon.rawValue) {
                                ForEach(sorted(items)) { row($0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Courses")
            .appChrome {
                Button("Copier la liste", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = listText(all)
                    toast.show("Liste copiée")
                }
                .disabled(all.isEmpty)
                ShareLink(item: listText(all)) { Label("Partager la liste", systemImage: "square.and.arrow.up") }
                    .disabled(all.isEmpty)
            }
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { d in
                let key = Days.adding(d, to: Days.today)
                let on = settings.shopDays.contains(d)
                Button {
                    var s = Set(settings.shopDays)
                    if on { s.remove(d) } else { s.insert(d) }
                    settings.shopDays = s.sorted()
                } label: {
                    VStack(spacing: 0) {
                        Text(Days.shortWeekday(key))
                        Text(Days.dayNumber(key)).font(.caption2).monospacedDigit()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(on ? Theme.accent : .primary)
                    .background(on ? Theme.accentSoft : Theme.surface2.opacity(0.5), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.accent : Theme.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Days.longLabel(key))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func row(_ l: Line) -> some View {
        let on = isChecked(l.ingredient)
        return Button {
            withAnimation(.snappy) {
                if on { settings.checked.removeAll { $0 == l.ingredient.uid } } else { settings.checked.append(l.ingredient.uid) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.accent : Theme.muted)
                Text(l.ingredient.name)
                    .strikethrough(on)
                    .foregroundStyle(on ? Theme.muted : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(l.text)
                    .fontWeight(on ? .regular : .bold)
                    .foregroundStyle(on ? Theme.muted : .primary)
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func listText(_ all: [Line]) -> String {
        let todo = all.filter { !isChecked($0.ingredient) }
        let days = settings.shopDays.count == 7 ? "7 prochains jours" : settings.shopDays.sorted().map { Days.shortLabel(Days.adding($0, to: Days.today)) }.joined(separator: ", ")
        var out = "Liste de courses (\(days))\n"
        for rayon in Rayon.allCases {
            let items = todo.filter { $0.ingredient.rayon == rayon }
                .sorted { $0.ingredient.name.localizedStandardCompare($1.ingredient.name) == .orderedAscending }
            guard !items.isEmpty else { continue }
            out += "\n\(rayon.rawValue)\n" + items.map { "- \($0.ingredient.name) : \($0.text)" }.joined(separator: "\n") + "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
