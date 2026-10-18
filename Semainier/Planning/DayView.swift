import SwiftData
import SwiftUI
import UIKit

struct DayView: View {
    @Binding var day: DayKey
    /// Les 7 jours de la bande (contient `day`).
    var stripDays: [DayKey]
    var entries: [PlanEntry]
    var ns: Namespace.ID
    var add: (Int) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Environment(\.modelContext) private var context
    @State private var expanded: Set<PersistentIdentifier> = []
    @State private var editingQty: PlanEntry?
    @State private var editingItem: ItemEdit?
    /// Début du dernier balayage : un bouton relâché juste après ne doit pas se déclencher.
    @State private var swipeStarted: Date?

    /// Exécute l'action d'un bouton, sauf si le toucher faisait partie d'un balayage.
    private func tap(_ action: () -> Void) {
        if let s = swipeStarted, Date.now.timeIntervalSince(s) < 0.8 { return }
        action()
    }

    /// Ligne de recette dont on modifie la quantité, pour ce plat uniquement.
    struct ItemEdit: Identifiable {
        let entry: PlanEntry
        let item: RecipeItem
        var id: PersistentIdentifier { item.persistentModelID }
    }

    var body: some View {
        let dayEntries = entries.on(day)
        let t = dayEntries.map(\.totals).sum
        let target = settings.targetKcal

        VStack(alignment: .leading, spacing: 16) {
            strip(target)
            totalCard(t, target: target)

            if dayEntries.isEmpty { emptyDay }

            VStack(alignment: .leading, spacing: 24) {
                ForEach(0..<4, id: \.self) { s in
                    slotSection(s, dayEntries.filter { $0.slot == s })
                }
            }
        }
        .contentShape(.rect)
        .sheet(item: $editingItem) { edit in
            if let g = edit.item.ingredient {
                let e = edit.entry, it = edit.item
                QuantitySheet(ingredient: g, initial: e.qty(for: it) * e.x,
                              note: "Modifie seulement ce plat du \(Days.longLabel(e.date).lowercased()). La recette n'est pas changée.",
                              original: it.qty * e.x,
                              onReset: { withAnimation(.snappy) { e.resetQty(for: it) } }) { q in
                    withAnimation(.snappy) { e.setQty(q, for: it) }
                }
            }
        }
        .sheet(item: $editingQty) { e in
            if let g = e.ingredient {
                QuantitySheet(ingredient: g, initial: e.qty) { e.qty = $0 }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jour-\(day)")
        // Balayer : gauche → jour suivant, droite → jour précédent, même en partant d'un bouton.
        .gesture(HorizontalSwipe(onBegin: { swipeStarted = .now }) { step in
            withAnimation(.modeSwitch) { day = Days.adding(step, to: day) }
        })
        .sensoryFeedback(.selection, trigger: day)
    }

    /// Bandeau des 7 jours : abréviation mono, chiffre Expanded, jauge du jour.
    /// Le jour choisi est en encre pleine : c'est le point d'arrivée de la pastille qui s'envole de la semaine.
    private func strip(_ target: Double) -> some View {
        HStack(spacing: 6) {
            ForEach(stripDays, id: \.self) { d in
                let k = entries.totals(d).kcal
                let on = d == day
                Button { tap { withAnimation(.modeSwitch) { day = d } } } label: {
                    VStack(spacing: 2) {
                        Text(Days.shortWeekday(d)).font(.system(size: 9, weight: .medium).monospaced())
                            .textCase(.uppercase).kerning(0.6)
                        Text(Days.dayNumber(d)).font(.title3.weight(.bold).width(.expanded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Capsule()
                            .fill(on && k > 0 && Theme.gauge(kcal: k, target: target) == Theme.ink ? Theme.bg : Theme.gauge(kcal: k, target: target))
                            .frame(width: 20, height: 3)
                            .opacity(k > 0 ? 1 : (on ? 0.35 : 1))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(on ? Theme.bg : Theme.ink)
                    .opacity(d < Days.today && !on ? 0.55 : 1)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: Theme.Radius.cell).fill(Theme.ink)
                                .matchedGeometryEffect(id: "jour", in: ns)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.Radius.cell).fill(Theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cell).strokeBorder(Theme.line))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Days.longLabel(d) + (k > 0 ? ", \(Fmt.n0(k)) kcal" : ""))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// Carte « étiquette » du total : filet de 3 pt, chiffre héros, jauge des kcal et jauges des macros.
    private func totalCard(_ t: Macros, target: Double) -> some View {
        let rest = target - t.kcal
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total du jour").sectionLabel()
                Spacer()
                Text(rest >= 0 ? "Reste \(Fmt.n0(rest)) kcal" : "Dépassé de \(Fmt.n0(-rest)) kcal")
                    .sectionLabel(rest >= 0 ? Theme.muted : Theme.over)
            }
            LabelRule()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.n0(t.kcal)).heroNumber()
                    .foregroundStyle(t.kcal > target ? Theme.over : Theme.ink)
                    .contentTransition(.numericText(value: t.kcal))
                Text("/ \(Fmt.n0(target)) kcal").foregroundStyle(Theme.muted).monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            ProgressBar(fraction: target > 0 ? t.kcal / target : 0,
                        color: t.kcal > target ? Theme.over : Theme.accent)
                .animation(.snappy, value: t.kcal)
            if t.kcal > 0 {
                MacroBars(totals: t, targets: settings.targets)
                    .padding(.top, 6)
            }
        }
        .card()
    }

    /// Jour vide : une étiquette vierge et une seule action.
    private var emptyDay: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.plaintext").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
            Text("\(Days.weekday(day)) est encore vide").font(.headline).foregroundStyle(Theme.ink)
            Text("Ajoute un plat, ou copie une journée déjà prévue depuis le menu •••")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { tap { add(0) } } label: { Label("Ajouter un plat", systemImage: "plus") }
                .buttonStyle(.primary)
                .padding(.top, 6)
        }
        .padding(.vertical, 26).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    /// Repas : étiquette mono, total, « + », répartition G · P · L puis les plats.
    private func slotSection(_ s: Int, _ list: [PlanEntry]) -> some View {
        let m = list.map(\.totals).sum
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Week.slots[s]).sectionLabel(Theme.ink)
                Spacer()
                if m.kcal > 0 {
                    Text("\(Text(Fmt.n0(m.kcal)).font(.callout.weight(.semibold).width(.expanded))) \(Text("kcal").font(.caption).foregroundStyle(Theme.muted))")
                        .monospacedDigit()
                }
                Button { tap { add(s) } } label: {
                    Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter un plat")
            }
            .padding(.horizontal, 2)

            if list.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
            } else {
                if list.count > 1 { MacroSplit(m: m, height: 3) }
                ForEach(list) { e in entryRow(e) }
            }
        }
    }

    /// Carte de plat : titre, méta, micro-barre G · P · L, chevron pour déplier les ingrédients.
    /// Un ingrédient seul montre sa quantité en pastille. Appui long : retirer.
    @ViewBuilder
    private func entryRow(_ e: PlanEntry) -> some View {
        if e.isValid {
            let open = expanded.contains(e.persistentModelID)
            let t = e.totals
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    tap {
                        if e.ingredient != nil {
                            editingQty = e
                        } else {
                            withAnimation(.snappy) {
                                if open { expanded.remove(e.persistentModelID) } else { expanded.insert(e.persistentModelID) }
                            }
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.title).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                            IngredientMacros(m: t)
                            MacroSplit(m: t, height: 3).frame(width: 140).padding(.top, 3)
                        }
                        Spacer(minLength: 4)
                        if let g = e.ingredient {
                            QuantityChip(text: Fmt.cook(e.qty * e.x, unit: g.unit))
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                                .rotationEffect(.degrees(open ? 180 : 0))
                                .frame(width: 30, height: 30)
                                .background(Theme.surface2, in: .circle)
                        }
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(e.ingredient != nil ? "Modifier la quantité" : open ? "Masquer les ingrédients" : "Afficher les ingrédients")
                .accessibilityAction(named: "Retirer") { withAnimation(.snappy) { context.delete(e) } }

                if open, let r = e.recipe {
                    VStack(spacing: 0) {
                        ForEach(r.sortedItems) { it in
                            if let g = it.ingredient {
                                let q = e.qty(for: it) * e.x
                                Rectangle().fill(Theme.line).frame(height: 1)
                                // Toute la ligne ouvre la saisie ; la pastille ✎ montre que c'est modifiable.
                                Button { tap { editingItem = ItemEdit(entry: e, item: it) } } label: {
                                    HStack(alignment: .center) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(g.name).font(.body).foregroundStyle(Theme.ink)
                                            IngredientMacros(m: g.macros(qty: q))
                                        }
                                        Spacer(minLength: 8)
                                        QuantityChip(text: Fmt.cook(q, unit: g.unit), modified: e.isOverridden(it))
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Modifier la quantité pour ce plat")
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 6)
                    // Fondu seul : la carte s'agrandit ou se réduit, la liste ne glisse plus par-dessus le titre.
                    .transition(.opacity)
                }
            }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.line.opacity(0.7)))
            .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.Radius.card))
            .contextMenu {
                if e.recipe != nil {
                    Button(open ? "Replier" : "Voir les ingrédients", systemImage: "list.bullet") {
                        withAnimation(.snappy) {
                            if open { expanded.remove(e.persistentModelID) } else { expanded.insert(e.persistentModelID) }
                        }
                    }
                }
                Button("Retirer", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy) { context.delete(e) }
                }
            }
        }
    }
}

/// Stepper −/+ de la portion, par pas de 0,1. Retiré de l'écran pour l'instant, gardé pour plus tard.
struct PortionStepper: View {
    @Binding var x: Double

    var body: some View {
        HStack(spacing: 0) {
            Button("Réduire la portion", systemImage: "minus") { x = Nutrition.stepped(x, by: -1) }
                .disabled(x <= 0.1)
            Text(Fmt.x(x))
                .font(.footnote.bold()).monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText(value: x))
            Button("Augmenter la portion", systemImage: "plus") { x = Nutrition.stepped(x, by: 1) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.subheadline.bold())
        .buttonRepeatBehavior(.enabled)
        .frame(height: 34)
        .padding(.horizontal, 8)
        .background(Theme.bg, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.line))
        .sensoryFeedback(.increase, trigger: x)
        .animation(.snappy, value: x)
    }
}

struct CopyDaySheet: View {
    var source: DayKey
    var entries: [PlanEntry]
    @Environment(\.modelContext) private var context
    @Environment(Toast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<DayKey> = []

    /// Les 14 prochains jours (aujourd'hui compris), sauf le jour copié.
    private var targets: [DayKey] { Days.range(from: Days.today, count: 14).filter { $0 != source } }

    var body: some View {
        NavigationStack {
            List {
                Group {
                Section {
                    ForEach(targets, id: \.self) { d in
                        Button {
                            if selected.contains(d) { selected.remove(d) } else { selected.insert(d) }
                        } label: {
                            HStack {
                                Text(Days.longLabel(d)).foregroundStyle(.primary)
                                if let r = Days.relative(d) { Text(r).foregroundStyle(Theme.muted) }
                                Spacer()
                                if selected.contains(d) { Image(systemName: "checkmark").foregroundStyle(Theme.accent).bold() }
                            }
                        }
                    }
                } footer: {
                    Text("Les jours choisis prennent exactement les mêmes plats et portions. Leur contenu actuel est remplacé.")
                }
                }
                .listRowBackground(Theme.surface)
            }
            .paperList()
            .navigationTitle("Copier le \(Days.longLabel(source).lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copier", role: .confirm) {
                        PlanActions.copy(day: source, to: selected, entries: entries, in: context)
                        toast.show("Copié vers \(selected.count) jour\(selected.count > 1 ? "s" : "")")
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Balayage horizontal qui annule le toucher des boutons sous le doigt dès qu'il démarre :
/// partir de « Ajouter un plat » ou d'un plat change de jour sans déclencher le bouton.
/// Ne démarre que pour un mouvement nettement horizontal, le défilement vertical reste libre.
struct HorizontalSwipe: UIGestureRecognizerRepresentable {
    /// Appelé dès que le balayage démarre (avant que le doigt ne se relève).
    var onBegin: () -> Void = {}
    /// +1 = jour suivant (balayage vers la gauche), -1 = jour précédent.
    var onSwipe: (Int) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        g.cancelsTouchesInView = true
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        if g.state == .began { onBegin() }
        guard g.state == .ended else { return }
        let t = g.translation(in: g.view), v = g.velocity(in: g.view)
        // Assez loin, ou un petit coup rapide.
        guard abs(t.x) > 60 || abs(v.x) > 600 else { return }
        onSwipe(t.x < 0 ? 1 : -1)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
