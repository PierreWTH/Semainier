import SwiftUI

/// Agenda : jours en colonnes, repas en lignes, colonne des repas fixe à gauche.
/// Tirer la grille vers la droite au-delà du premier jour étire une colonne « veille » entre les repas
/// et le premier jour ; tiré assez loin, au relâcher on passe sur les 7 jours précédents.
/// Tirer au-delà du dernier jour charge les 7 suivants.
struct WeekView: View {
    var entries: [PlanEntry]
    /// Jours affichés, dans l'ordre.
    var days: [DayKey]
    var selected: DayKey
    var ns: Namespace.ID
    var openDay: (DayKey) -> Void
    var add: (DayKey, Int) -> Void
    /// Charger 7 jours de plus : `true` avant, `false` après.
    var extend: (_ backward: Bool) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var scrollX: CGFloat = 0
    /// Case survolée pendant un glisser-déposer.
    @State private var dropTarget: SlotRef?
    @State private var dropCount = 0
    /// Recette ou ingrédient ouvert depuis le menu d'un plat.
    @State private var viewingRecipe: RecipeEditTarget?
    @State private var viewingIngredient: IngredientEditTarget?
    @State private var width: CGFloat = 390
    @State private var position: ScrollPosition
    /// Distance tirée au-delà du bord gauche / droit, et seuil franchi.
    @State private var pull = EdgePull()
    @State private var armed: Bool?
    @State private var interacting = false

    private let labelWidth: CGFloat = 70
    /// Distance à tirer pour charger d'autres jours.
    private let pullThreshold: CGFloat = 70
    private let today = Days.today

    private var colWidth: CGFloat { max(128, (width - labelWidth) / 7 - 1) }
    /// Largeur d'une colonne avec son trait de séparation.
    private var colStep: CGFloat { colWidth + 1 }


    init(entries: [PlanEntry], days: [DayKey], selected: DayKey, ns: Namespace.ID,
         openDay: @escaping (DayKey) -> Void, add: @escaping (DayKey, Int) -> Void,
         extend: @escaping (Bool) -> Void) {
        self.entries = entries
        self.days = days
        self.selected = selected
        self.ns = ns
        self.openDay = openDay
        self.add = add
        self.extend = extend
        // La grille s'ouvre sur la colonne du jour sélectionné (colonnes de 128 pt sur iPhone),
        // pour que la pastille du jour revienne se poser au bon endroit lors de la bascule.
        let index = days.firstIndex(of: selected) ?? 0
        _position = State(initialValue: ScrollPosition(x: CGFloat(index) * 129))
    }

    var body: some View {
        let target = settings.targetKcal
        let totals = days.map { entries.totals($0) }
        let filled = totals.filter { $0.kcal > 0 }
        let avg = filled.isEmpty ? 0 : filled.map(\.kcal).reduce(0, +) / Double(filled.count)
        let onTarget = totals.filter { Nutrition.status(kcal: $0.kcal, target: target) == .ok }.count

        VStack(alignment: .leading, spacing: 16) {
            stats(avg, onTarget, filled.isEmpty, totals: totals)

            grid()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }

            Text("Touche un jour ou un plat pour ouvrir le détail. Tire la grille au-delà du premier ou du dernier jour pour en voir plus.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        .sheet(item: $viewingRecipe) { RecipeEditor(recipe: $0.recipe) }
        .sheet(item: $viewingIngredient) { IngredientEditor(target: $0) }
    }

    /// Moyenne en chiffre héros, ouverte par le filet ; à droite, un point par jour (couleur de sa jauge).
    private func stats(_ avg: Double, _ onTarget: Int, _ empty: Bool, totals: [Macros]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabelRule()
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(empty ? "—" : Fmt.n0(avg)).heroNumber(44).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("kcal / jour\nen moyenne").font(.footnote).foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(Array(totals.prefix(14).enumerated()), id: \.offset) { _, t in
                            let c = Theme.gauge(kcal: t.kcal, target: settings.targetKcal)
                            Circle().fill(c == Theme.ink ? Theme.muted : c).frame(width: 7, height: 7)
                        }
                    }
                    Text("\(onTarget)/\(days.count) dans la cible ±3 %").sectionLabel()
                        .lineLimit(1).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func grid() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    pinned(Color.clear.frame(height: 1))
                    ForEach(days, id: \.self) { header($0) }
                }
                ForEach(0..<4, id: \.self) { s in
                    GridRow {
                        pinned(slotLabel(Week.slotsShort[s]))
                        ForEach(days, id: \.self) { cell(day: $0, slot: s) }
                    }
                }
                GridRow {
                    pinned(slotLabel("Total"), center: true)
                    ForEach(days, id: \.self) { d in foot(d, entries.totals(d)) }
                }
            }
            .background(Theme.line)
            // Hauteur idéale par ligne : les cellules en maxHeight .infinity remplissent alors leur ligne.
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: EdgePull.self) { g in
            let x = g.contentOffset.x + g.contentInsets.leading
            let maxX = max(0, g.contentSize.width - g.containerSize.width)
            return EdgePull(x: max(0, x), leading: max(0, -x), trailing: max(0, x - maxX))
        } action: { _, p in
            scrollX = p.x
            pull = p
            // Seuil franchi pendant le tiré : retour haptique, le chargement se fait au relâcher.
            if p.leading > pullThreshold { armed = true } else if p.trailing > pullThreshold { armed = false }
            // Revenu sous le seuil avant de relâcher : on annule.
            else if interacting { armed = nil }
        }
        .onScrollPhaseChange { old, new in
            interacting = new == .interacting
            guard old == .interacting, new != .interacting, let backward = armed else { return }
            armed = nil
            load(backward: backward)
        }
        // Revenu sur aujourd'hui (bouton « Aujourd'hui ») : la grille se recale au début.
        .onChange(of: days.first) { old, new in
            guard let old, let new, new > old else { return }
            withAnimation(.snappy) { position.scrollTo(x: CGFloat(days.firstIndex(of: selected) ?? 0) * colStep) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new != nil }
        .background(Theme.surface)
        // Colonne « veille » qui s'étire entre les repas (fixes) et le premier jour.
        .overlay(alignment: .leading) { stretchColumn.padding(.leading, labelWidth) }
        .overlay(alignment: .trailing) { pullHint(backward: false, distance: pull.trailing) }
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }

    /// Charge 7 jours de plus. Vers l'arrière, on passe ensuite sur ces jours précédents :
    /// la grille reste d'abord en place (les colonnes ajoutées à gauche la décalent), puis glisse jusqu'à eux.
    private func load(backward: Bool) {
        extend(backward)
        if backward {
            let x = scrollX + 7 * colStep
            DispatchQueue.main.async {
                position.scrollTo(x: x)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.smooth(duration: 0.45)) { position.scrollTo(x: max(0, x - 7 * colStep)) }
                }
            }
        }
    }

    /// La veille du premier jour, étirée à la largeur tirée : son nom en haut, la double flèche au milieu.
    @ViewBuilder
    private var stretchColumn: some View {
        let distance = pull.leading
        if distance > 4, let first = days.first {
            let ready = distance > pullThreshold
            VStack(spacing: 0) {
                Text(Days.shortLabel(Days.adding(-1, to: first)))
                    .font(.subheadline.bold()).foregroundStyle(Theme.muted)
                    .lineLimit(1).fixedSize()
                    .padding(.top, 12)
                    .opacity(distance > 60 ? 1 : 0)
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "chevron.left.2")
                        .font(.body.bold())
                        .symbolEffect(.bounce, value: ready)
                    Text(ready ? "Relâche" : "Jours\nprécédents")
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2).fixedSize()
                        .opacity(distance > 50 ? 1 : 0)
                }
                .foregroundStyle(ready ? Theme.accent : Theme.muted)
                Spacer()
            }
            .frame(width: distance)
            .frame(maxHeight: .infinity)
            .background(ready ? Theme.accentSoft : Theme.surface2.opacity(0.6))
            .clipped()
            .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
            .animation(.snappy, value: ready)
            .allowsHitTesting(false)
        }
    }

    /// Indicateur qui apparaît dans l'espace révélé quand on tire au-delà d'un bord.
    @ViewBuilder
    private func pullHint(backward: Bool, distance: CGFloat) -> some View {
        if distance > 4 {
            let ready = distance > pullThreshold
            VStack(spacing: 6) {
                Image(systemName: backward ? "chevron.left.2" : "chevron.right.2")
                    .font(.body.bold())
                    .symbolEffect(.bounce, value: ready)
                Text(ready ? "Relâche" : backward ? "Jours\nprécédents" : "Jours\nsuivants")
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(ready ? Theme.accent : Theme.muted)
            .frame(width: max(distance, 1))
            .opacity(min(1, Double(distance / pullThreshold)))
            .allowsHitTesting(false)
        }
    }

    private func slotLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .medium).monospaced()).textCase(.uppercase).kerning(0.5)
            .foregroundStyle(Theme.muted)
            .lineLimit(2).minimumScaleFactor(0.8)
    }

    /// Cellule de la colonne de gauche, décalée pour rester visible pendant le défilement.
    private func pinned(_ content: some View, center: Bool = false) -> some View {
        content
            .padding(.horizontal, 7).padding(.vertical, 10)
            .frame(width: labelWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: center ? .leading : .topLeading)
            .background(Theme.surface)
            .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
            // Toujours fixe à l'écran, même quand la grille rebondit au bord.
            .offset(x: pull.x - pull.leading)
            .zIndex(1)
    }

    private func dayBackground(_ d: DayKey) -> Color {
        d == today ? Theme.accentWash : d < today ? Theme.surface2.opacity(0.35) : .clear
    }

    private func header(_ d: DayKey) -> some View {
        Button { openDay(d) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Days.shortWeekday(d)).font(.headline)
                    .foregroundStyle(d < today ? Theme.muted : Theme.ink)
                Text(Days.dayNumber(d))
                    .font(.footnote.weight(.semibold).width(.expanded)).monospacedDigit()
                    .foregroundStyle(d == today ? Theme.onAccent : Theme.muted)
                    .padding(.horizontal, d == today ? 7 : 0).padding(.vertical, 1)
                    .background(d == today ? Theme.accent : .clear, in: .capsule)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .frame(width: colWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            // Point de départ (et d'arrivée) de la pastille du jour lors de la bascule.
            if d == selected { Color.clear.matchedGeometryEffect(id: "jour", in: ns) }
        }
        .background(dayBackground(d))
        .background(Theme.surface)
        .accessibilityLabel("Ouvrir \(Days.longLabel(d))")
    }

    private func cell(day d: DayKey, slot s: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(entries.on(d).filter { $0.slot == s }) { e in
                if e.isValid {
                    Button { openDay(d) } label: {
                        chipContent(e)
                            .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.Radius.cell))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("entry-\(e.title)")
                    // Appui long : doigt immobile → menu ; doigt qui bouge → le plat se détache.
                    // Le déposer ailleurs le duplique (« même petit-déj demain ») ; déplacer passe par le menu.
                    .draggable(e.uid) { chipPreview(e) }
                    .contextMenu {
                        Button("Ouvrir \(Days.longLabel(d))", systemImage: "calendar") { openDay(d) }
                        if let r = e.recipe {
                            Button("Voir la recette", systemImage: "fork.knife") { viewingRecipe = RecipeEditTarget(recipe: r) }
                        } else if let g = e.ingredient {
                            Button("Voir l'ingrédient", systemImage: "leaf") { viewingIngredient = IngredientEditTarget(ingredient: g) }
                        }
                        Menu("Copier vers", systemImage: "plus.square.on.square") {
                            dayButtons(except: d) { duplicate(e, day: $0, slot: s) }
                        }
                        Menu("Déplacer vers", systemImage: "arrow.left.arrow.right") {
                            dayButtons(except: d) { move(e, day: $0, slot: s) }
                        }
                        Button("Retirer", systemImage: "trash", role: .destructive) {
                            withAnimation(.snappy) { context.delete(e) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button { add(d, s) } label: {
                Image(systemName: "plus").font(.footnote.bold())
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .foregroundStyle(Theme.muted)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter un plat : \(Days.longLabel(d)), \(Week.slots[s].lowercased())")
        }
        .padding(6)
        .frame(width: colWidth, alignment: .topLeading)
        .frame(minHeight: 64, maxHeight: .infinity, alignment: .topLeading)
        .background(dropTarget == SlotRef(date: d, slot: s) ? Theme.accent.opacity(0.14) : .clear)
        .background(dayBackground(d))
        .background(Theme.surface)
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first, let e = entries.first(where: { $0.uid == uid }) else { return false }
            // Reposé sur sa propre case : rien à faire.
            guard e.date != d || e.slot != s else { return false }
            duplicate(e, day: d, slot: s)
            return true
        } isTargeted: { on in
            let ref = SlotRef(date: d, slot: s)
            withAnimation(.snappy) {
                if on { dropTarget = ref } else if dropTarget == ref { dropTarget = nil }
            }
        }
        .sensoryFeedback(.success, trigger: dropCount)
        .accessibilityElement(children: .contain)
        // Index dans la grille (0 = premier jour affiché), pour les tests d'interface.
        .accessibilityIdentifier("cell-\(days.firstIndex(of: d) ?? -1)-\(s)")
    }

    private func move(_ e: PlanEntry, day: DayKey, slot: Int) {
        withAnimation(.snappy) { PlanActions.move(e, date: day, slot: slot, in: context) }
        dropCount += 1
    }

    private func duplicate(_ e: PlanEntry, day: DayKey, slot: Int) {
        withAnimation(.snappy) { PlanActions.duplicate(e, date: day, slot: slot, in: context) }
        dropCount += 1
    }

    /// Les jours affichés sauf `day`, pour les sous-menus Copier / Déplacer.
    @ViewBuilder
    private func dayButtons(except day: DayKey, action: @escaping (DayKey) -> Void) -> some View {
        ForEach(days.filter { $0 != day }, id: \.self) { other in
            Button(Days.longLabel(other)) { action(other) }
        }
    }

    /// Case pleine : nom sur deux lignes, kcal en Expanded, portion en pastille, micro-barre G · P · L.
    private func chipContent(_ e: PlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(e.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Text(Fmt.n0(e.totals.kcal)).font(.caption.weight(.semibold).width(.expanded)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                if let g = e.ingredient {
                    tag(Fmt.cook(e.qty * e.x, unit: g.unit))
                } else if e.x != 1 {
                    tag(Fmt.x(e.x))
                }
            }
            MacroSplit(m: e.totals, height: 3).padding(.top, 2)
        }
        .padding(.horizontal, 8).padding(.top, 7).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: .rect(cornerRadius: Theme.Radius.cell))
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium).monospaced()).foregroundStyle(Theme.accent)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.accentSoft, in: .capsule)
    }

    /// Aperçu du plat pendant le glisser.
    private func chipPreview(_ e: PlanEntry) -> some View {
        chipContent(e).frame(width: colWidth - 12)
    }

    /// Total du jour en Expanded, souligné de sa jauge (encre, vert dans ±3 %, brique au-delà).
    private func foot(_ d: DayKey, _ t: Macros) -> some View {
        let target = settings.targetKcal
        let c = Theme.gauge(kcal: t.kcal, target: target)
        return Button { openDay(d) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(t.kcal > 0 ? Fmt.n0(t.kcal) : "—")
                    .font(.callout.weight(.bold).width(.expanded)).monospacedDigit()
                    .foregroundStyle(c == Theme.over ? Theme.over : Theme.ink)
                Capsule().fill(Theme.surface2).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(c).frame(width: g.size.width * min(target > 0 ? t.kcal / target : 0, 1))
                        }
                    }
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .frame(width: colWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(dayBackground(d))
        .background(Theme.surface)
        .accessibilityLabel("\(Days.longLabel(d)) : \(Fmt.n0(t.kcal)) kcal")
    }

}

/// Position horizontale de la grille et distance tirée au-delà de chaque bord.
struct EdgePull: Equatable {
    var x: CGFloat = 0
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}
