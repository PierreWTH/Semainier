import SwiftData
import SwiftUI
import UIKit

struct ShoppingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Query(filter: PlanEntry.prochainsJours) private var entries: [PlanEntry]

    private func isChecked(_ g: Ingredient) -> Bool { settings.checked.contains(g.uid) }

    var body: some View {
        // shopDays : décalages à partir d'aujourd'hui (0 = aujourd'hui … 6).
        let liste = ListeCourses(entries: entries, days: Days.chosen(settings.shopDays))
        let coches = Set(settings.checked)
        let done = liste.lignes.filter { coches.contains($0.ingredient.uid) }.count
        let texte = liste.texte(coches: coches, jours: ListeCourses.joursTexte(settings.shopDays))

        NavigationStack {
            List {
                Group {
                    // En en-tête, hors cellule : la cellule rognerait le conteneur avec ses propres coins,
                    // et les rayons du conteneur et des boutons ne seraient plus concentriques.
                    Section {
                    } header: {
                        ShopDayPicker()
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        // Compteur en pied de section, hors cellule : le trait épais n'est pas rogné par les coins arrondis.
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Total des ingrédients pour les jours choisis, portions ajustées comprises.")
                                .font(.footnote).foregroundStyle(Color.texte2)
                            if !liste.isEmpty {
                                counter(done: done, total: liste.lignes.count)
                                    .padding(.top, 24)
                            }
                        }
                    }

                    if liste.isEmpty {
                        ContentUnavailableView("Rien à acheter pour l'instant", systemImage: "basket",
                                               description: Text("Placer des plats dans le planning : la liste se remplit toute seule."))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(liste.parRayon(coches: coches), id: \.rayon) { rayon, items in
                            Section(rayon.rawValue) {
                                ForEach(items) { row($0) }
                            }
                        }
                    }
                }
                .listRowBackground(Color.surface)
            }
            .fondEcran()
            .navigationTitle("Courses")
            .appChrome {
                Button("Copier la liste", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = texte
                    toast.show("Liste copiée")
                }
                .disabled(liste.isEmpty)
                ShareLink(item: texte) { Label("Partager la liste", systemImage: "square.and.arrow.up") }
                    .disabled(liste.isEmpty)
            }
        }
    }

    /// « 8 / 25 dans le panier », « Tout décocher », puis le trait épais.
    private func counter(done: Int, total: Int) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(done)").police(.compteur).foregroundStyle(Color.texte)
                        .contentTransition(.numericText(value: Double(done)))
                    Text("/ \(total) dans le panier").font(.body).foregroundStyle(Color.texte2)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Tout décocher") { withAnimation { settings.checked = [] } }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .disabled(done == 0)
            }
            Rectangle().fill(Color.texte).frame(height: 3)
        }
        .textCase(nil)
    }

    private func row(_ l: ListeCourses.Ligne) -> some View {
        let on = isChecked(l.ingredient)
        let q = QuantityParts(l.text)
        return Button {
            withAnimation(.snappy) {
                if on { settings.checked.removeAll { $0 == l.ingredient.uid } } else { settings.checked.append(l.ingredient.uid) }
            }
        } label: {
            HStack(spacing: 12) {
                CercleCoche(on: on, size: 26)
                Text(l.ingredient.name)
                    .strikethrough(on)
                    .foregroundStyle(on ? Color.texte2 : Color.texte)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(q.number).police(.quantiteCourses)
                        .foregroundStyle(on ? Color.texte2 : Color.texte)
                    if let unit = q.unit {
                        Text(unit).font(.callout).foregroundStyle(Color.texte2)
                    }
                }
                .monospacedDigit()
            }
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Ligne de 56 pt au total : pas de marge verticale en plus de la liste.
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

}

/// Les 7 prochains jours à cocher, pour les courses et pour « À préparer » (onglet Cuisine) : une seule sélection,
/// on fait les courses et on cuisine pour les mêmes jours.
struct ShopDayPicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { d in
                let key = Days.adding(d, to: Days.today)
                let on = settings.shopDays.contains(d)
                Button {
                    var s = Set(settings.shopDays)
                    if on { s.remove(d) } else { s.insert(d) }
                    settings.shopDays = s.sorted()
                } label: {
                    VStack(spacing: 1) {
                        Text(Days.shortWeekday(key)).font(.footnote.weight(.semibold))
                        Text(Days.dayNumber(key))
                            .font(.system(.footnote, design: .rounded).weight(on ? .semibold : .regular))
                            .monospacedDigit()
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(on ? Color.accentColor : Color.texte2)
                    .background(on ? Color.accentDoux : .clear, in: .rect(cornerRadius: Arrondi.puceJour))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Days.longLabel(key))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Color.surface, in: .rect(cornerRadius: Arrondi.cartePlat))
    }
}
