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

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.n0(t.kcal)).font(.system(size: 38, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: t.kcal))
                        Text("/ \(Fmt.n0(target)) kcal").foregroundStyle(Theme.muted)
                    }
                    .monospacedDigit()
                    ProgressBar(fraction: target > 0 ? t.kcal / target : 0,
                                color: t.kcal > target ? Theme.over : Theme.accent)
                        .animation(.snappy, value: t.kcal)
                }
                MacroBars(totals: t, targets: settings.targets)
            }
            .card()

            ForEach(0..<4, id: \.self) { s in
                slotSection(s, dayEntries.filter { $0.slot == s })
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

    private func strip(_ target: Double) -> some View {
        HStack(spacing: 6) {
            ForEach(stripDays, id: \.self) { d in
                let k = entries.totals(d).kcal
                let on = d == day
                Button { tap { withAnimation(.modeSwitch) { day = d } } } label: {
                    VStack(spacing: 3) {
                        Text(Days.shortLabel(d)).font(.footnote.bold())
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .opacity(d < Days.today && !on ? 0.6 : 1)
                        Text(k > 0 ? Fmt.n0(k) : "—").font(.caption2).monospacedDigit()
                            .foregroundStyle(on ? Color(uiColor: .systemBackground).opacity(0.85) : Theme.muted)
                        ProgressBar(fraction: target > 0 ? k / target : 0,
                                    color: Theme.color(Nutrition.status(kcal: k, target: target)), height: 4)
                            .padding(.horizontal, 6)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(on ? Color(uiColor: .systemBackground) : .primary)
                    .background {
                        // La pastille bleue glisse d'un jour à l'autre, et vient de la colonne touchée dans la semaine.
                        if on {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.accent)
                                .matchedGeometryEffect(id: "jour", in: ns)
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Days.longLabel(d))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func slotSection(_ s: Int, _ list: [PlanEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Week.slots[s]).sectionLabel()
                Spacer()
                let k = list.map(\.totals.kcal).reduce(0, +)
                if k > 0 { Text("\(Fmt.n0(k)) kcal").font(.footnote).foregroundStyle(Theme.muted).monospacedDigit() }
            }
            .padding(.horizontal, 2)

            if !list.isEmpty {
                // Récap du repas : répartition des kcal entre G / P / L.
                let m = list.map(\.totals).sum
                VStack(alignment: .leading, spacing: 5) {
                    MacroLine(m: m, unit: " g").font(.caption).foregroundStyle(Theme.muted)
                    MacroSplit(m: m, height: 4)
                }
                .padding(.horizontal, 2)
            }

            ForEach(list) { e in entryRow(e) }

            Button { tap { add(s) } } label: {
                Label("Ajouter un plat", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder
    private func entryRow(_ e: PlanEntry) -> some View {
        if e.isValid {
            let open = expanded.contains(e.persistentModelID)
            let t = e.totals
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).fontWeight(.semibold).multilineTextAlignment(.leading)
                            Group {
                                if let g = e.ingredient {
                                    Text("\(Fmt.cook(e.qty * e.x, unit: g.unit)) · \(Fmt.n0(t.kcal)) kcal · \(MacroLine.text(t))")
                                } else {
                                    Text("\(Fmt.n0(t.kcal)) kcal · \(MacroLine.text(t))")
                                }
                            }
                            .font(.caption).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(e.ingredient != nil ? "Modifier la quantité" : open ? "Masquer les ingrédients" : "Afficher les ingrédients")

                    Button("Retirer \(e.title)", systemImage: "xmark") {
                        tap { withAnimation(.snappy) { context.delete(e) } }
                    }
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 34)
                    .buttonStyle(.borderless)
                }

                if open, let r = e.recipe {
                    VStack(spacing: 8) {
                        ForEach(r.sortedItems) { it in
                            if let g = it.ingredient {
                                let q = e.qty(for: it) * e.x
                                // Toute la ligne ouvre la saisie ; la quantité en pastille montre que c'est modifiable.
                                Button { tap { editingItem = ItemEdit(entry: e, item: it) } } label: {
                                    HStack(alignment: .center) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(g.name).font(.subheadline)
                                            IngredientMacros(m: g.macros(qty: q))
                                        }
                                        Spacer(minLength: 8)
                                        QuantityChip(text: Fmt.cook(q, unit: g.unit), modified: e.isOverridden(it))
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Modifier la quantité pour ce plat")
                            }
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 8).padding(.trailing, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    // Fondu seul : la carte s'agrandit ou se réduit, la liste ne glisse plus par-dessus le titre.
                    .transition(.opacity)
                }
            }
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
            .background(Theme.surface, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
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
