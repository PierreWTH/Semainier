import SwiftUI
import UniformTypeIdentifiers

/// Agenda : jours en colonnes, repas en lignes, dans une grille UIKit (`WeekGrid`) qui défile dans les deux sens et
/// garde l'en-tête des jours (total et jauge) figé en haut. Une semaine à la fois ; tirer au bord passe à la voisine.
/// Pincer bascule vers la vue d'ensemble : les 7 jours dans la largeur, kcal et nombre de plats par repas.
struct WeekView: View {
    var index: PlanIndex
    /// Jours affichés, dans l'ordre.
    var days: [DayKey]
    var selected: DayKey
    var openDay: (DayKey) -> Void
    var add: (DayKey, Meal) -> Void
    /// Passer à la semaine voisine : `true` la suivante, `false` la précédente.
    var shift: (_ forward: Bool) -> Void
    /// Change quand la grille doit revenir sur `selected` (bouton du jour).
    var recenter: Int
    /// Aujourd'hui est-il à l'écran dans la grille ?
    var todayVisible: (Bool) -> Void
    /// Vue d'ensemble : les 7 jours tiennent dans la largeur, chaque case résumée.
    @Binding var overview: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Case survolée pendant un glisser-déposer.
    @State private var dropTarget: SlotRef?
    @State private var dropCount = 0
    /// Tirer en cours vers la semaine voisine (pastille au bord de l'écran).
    @State private var pull: WeekPull?
    @State private var meter = PullMeter()
    /// Plat en cours de glisser, retenu dès le départ du geste.
    @State private var drag = DragSource()
    /// Cases dont les ingrédients seuls regroupés sont dépliés.
    @State private var unfolded: Set<SlotRef> = []
    /// Recette ou ingrédient ouvert depuis le menu d'un plat.
    @State private var viewingRecipe: RecipeEditTarget?
    @State private var viewingIngredient: IngredientEditTarget?
    @State private var dishEdit: DishEdit?
    @State private var savingLone: LoneToRecipe?
    @State private var editingTargets = false
    @State private var width: CGFloat = 390

    /// À partir de ce nombre d'ingrédients seuls dans une case, ils tiennent sur une seule tuile repliée.
    private let groupFrom = 3
    private let today = Days.today
    private let size = GridSizes()

    /// 162 pt : deux jours entiers et le début du troisième sur iPhone.
    /// Aux tailles d'accessibilité, une colonne et demie visible plutôt qu'un texte réduit.
    /// Vue d'ensemble : les 7 colonnes dans la largeur.
    private var colWidth: CGFloat {
        if overview { return width / 7 - 1 }
        return typeSize.isAccessibilitySize ? max(162, width / 1.5 - 1) : 162
    }
    /// Largeur d'une colonne avec son trait de séparation.
    private var colStep: CGFloat { colWidth + 1 }

    init(index: PlanIndex, days: [DayKey], selected: DayKey,
         openDay: @escaping (DayKey) -> Void, add: @escaping (DayKey, Meal) -> Void,
         shift: @escaping (Bool) -> Void, recenter: Int = 0, todayVisible: @escaping (Bool) -> Void = { _ in },
         overview: Binding<Bool> = .constant(false)) {
        self.index = index
        self.days = days
        self.selected = selected
        self.openDay = openDay
        self.add = add
        self.shift = shift
        self.recenter = recenter
        self.todayVisible = todayVisible
        self._overview = overview
    }

    var body: some View {
        let target = settings.targetKcal
        let week = index.stats(days, target: target)

        VStack(alignment: .leading, spacing: 0) {
            // La moyenne reste fixe au-dessus de la grille : ni le défilement, ni le changement de semaine, ni la
            // bascule de zoom ne la déplacent (seuls ses chiffres changent).
            stats(week.average, week.withinTarget, week.empty).padding(.bottom, 12)
            WeekGrid(days: days, selected: selected, width: width, colWidth: colWidth,
                     headerHeight: overview ? size.overviewHeader : size.header, bandHeight: size.band, layoutKey: layoutKey,
                     cellKey: cellKey, recenter: recenter,
                     header: { AnyView(header($0, target)) },
                     band: { AnyView(band($0, slot: $1)) },
                     cell: { overview ? AnyView(overviewCell(day: $0, slot: $1)) : AnyView(cell(day: $0, slot: $1, measuring: $2)) },
                     footer: AnyView(footer),
                     shift: shift,
                     visible: { [today] in todayVisible($0.contains(today)) },
                     canDrop: { [overview] in !overview && drag.uid != nil },
                     hover: { ref in withAnimation(.snappy) { dropTarget = ref } },
                     drop: dropped,
                     pull: { p in withAnimation(.snappy) { pull = p } },
                     meter: meter,
                     zoom: { out in if overview != out { overview = out } })
                .frame(maxHeight: .infinity)
                // Une pastille par bord, chacune apparaît sur place : un seul emplacement dont l'alignement changeait
                // dans l'animation la faisait traverser l'écran depuis l'autre bord.
                .overlay(alignment: .leading) {
                    if let pull, !pull.forward { pullBadge(pull).padding(.horizontal, Spacing.margin) }
                }
                .overlay(alignment: .trailing) {
                    if let pull, pull.forward { pullBadge(pull).padding(.horizontal, Spacing.margin) }
                }
                // Une vibration au seuil : lâcher maintenant change de semaine.
                .sensoryFeedback(trigger: pull?.armed == true) { _, armed in armed ? .impact(weight: .medium) : nil }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .sheet(item: $viewingRecipe) { RecipeEditor(recipe: $0.recipe) }
        .sheet(item: $viewingIngredient) { IngredientEditor(target: $0) }
        .saveLoneAsRecipe($savingLone)
        .sheet(isPresented: $editingTargets) { TargetsSheet() }
        .dishEdit($dishEdit)
    }

    /// « 2 378 / 2 600 kcal en moyenne » (moyenne en `ok` / `depassement` selon la cible) et « 1 / 7 dans la cible ».
    /// L'objectif n'a pas de bulle en vue Semaine : il est ici, et toucher la ligne ouvre « Mes objectifs ».
    private func stats(_ avg: Double, _ onTarget: Int, _ empty: Bool) -> some View {
        let target = settings.targetKcal
        let average = HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(empty ? "—" : Fmt.n0(avg)).appFont(.weekAverage)
                .foregroundStyle(empty ? Color.textTertiary : Threshold.dayColor(avg, target: target, otherwise: .textPrimary))
            Text("/ \(Fmt.n0(target)) kcal en moyenne").font(.system(size: size.statsUnit)).foregroundStyle(Color.textSecondary)
        }
        let count = Text("\(onTarget) / \(days.count) dans la cible")
            .font(.system(size: size.statsCount)).foregroundStyle(Color.textSecondary)
        return Button { editingTargets = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    average
                    Spacer(minLength: 8)
                    count
                }
                VStack(alignment: .leading, spacing: 2) {
                    average
                    count
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(empty ? "Aucun plat cette semaine, objectif \(Fmt.n0(target)) kilocalories par jour"
                            : "\(Fmt.n0(avg)) kilocalories par jour en moyenne, objectif \(Fmt.n0(target)), \(onTarget) jours sur \(days.count) dans la cible")
        .accessibilityHint("Modifier mes objectifs")
    }

    /// Empreinte de ce qui fait varier la hauteur des lignes : la grille remesure quand elle change.
    /// Seuls les jours affichés comptent (un plat déplacé vers eux change de date, ce qui recrée l'index).
    private var layoutKey: Int {
        var h = Hasher()
        for e in days.flatMap(index.entries(on:)) {
            h.combine(e.uid); h.combine(e.date); h.combine(e.slot); h.combine(e.x); h.combine(e.qty)
            h.combine(e.title); h.combine(e.isValid); h.combine(e.recipe?.byPiece)
        }
        h.combine(unfolded)
        h.combine(typeSize)
        h.combine(overview)
        return h.finalize()
    }

    /// Empreinte de ce qui fait varier la hauteur d'une case : la grille ne remesure que les cases où elle change.
    private func cellKey(_ d: DayKey, _ s: Meal) -> Int {
        var h = Hasher()
        for e in index.entries(on: d) where e.meal == s {
            h.combine(e.uid); h.combine(e.order); h.combine(e.x); h.combine(e.qty)
            h.combine(e.title); h.combine(e.isValid); h.combine(e.recipe?.byPiece)
        }
        h.combine(unfolded.contains(SlotRef(date: d, meal: s)))
        h.combine(typeSize)
        h.combine(overview)
        return h.finalize()
    }

    /// « 2 – 8 nov. » au bord de l'écran pendant le tirer.
    private func pullBadge(_ p: WeekPull) -> some View {
        let first = Days.adding(p.forward ? 7 : -7, to: days.first ?? Days.today)
        return PullBadge(text: Days.shortRangeText(first, Days.adding(6, to: first)), pull: p, meter: meter)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityHidden(true)
    }

    private var footer: some View {
        Text(overview
             ? "Toucher un jour pour l'ouvrir. Écarter deux doigts pour revenir au détail, tirer au bord pour changer de semaine."
             : "Toucher un jour ou un plat pour ouvrir le détail. Tirer au-delà du bord de la grille pour passer à la semaine voisine, pincer pour voir toute la semaine.")
            .font(.footnote).foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16).padding(.bottom, 24)
    }

    private func totals(of d: DayKey) -> Macros { index.totals(on: d) }

    private func dayBackground(_ d: DayKey) -> Color {
        d == today ? .todayColumn : .clear
    }

    /// « Ven 16 ………… 2 360 kcal » ; le trait du bas est la jauge du jour.
    /// Vue d'ensemble : « Ven », « 16 », « 2 360 » les uns sous les autres.
    private func header(_ d: DayKey, _ target: Double) -> some View {
        let isToday = d == today
        let kcal = totals(of: d).kcal
        let status = Nutrition.dayStatus(kcal: kcal, target: target)
        return Button { openDay(d) } label: {
            Group {
                if overview { overviewHeader(d, kcal, target) } else { headerLine(d, kcal, target) }
            }
            .frame(width: colWidth, height: overview ? size.overviewHeader : size.header,
                   alignment: overview ? .center : .leading)
            .overlay(alignment: .bottom) {
                gauge(kcal, target, belowColor: isToday ? .accentColor : .textSecondary)
            }
            .background(dayBackground(d))
            .background(Color.appBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Days.weekday(d)) \(Days.dayNumber(d)), \(Fmt.n0(kcal)) kilocalories, \(status.label)")
        .accessibilityHint("Ouvrir le jour")
    }

    private func dayNumber(_ d: DayKey) -> some View {
        let isToday = d == today
        return Text(Days.dayNumber(d)).appFont(.dateStamp)
            .foregroundStyle(isToday ? Color.onAccent : Color.textSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background {
                if isToday { RoundedRectangle(cornerRadius: Radius.dateStamp).fill(Color.accentColor) }
            }
    }

    private func overviewHeader(_ d: DayKey, _ kcal: Double, _ target: Double) -> some View {
        VStack(spacing: 2) {
            Text(Days.shortWeekday(d)).font(.system(size: size.headerUnit + 1, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            dayNumber(d)
            Text(kcal > 0 ? Fmt.n0(kcal) : "—").font(.system(size: size.headerUnit + 1, weight: .semibold, design: .rounded))
                .foregroundStyle(kcal > 0 ? Threshold.dayColor(kcal, target: target, otherwise: .textPrimary) : Color.textTertiary)
                .monospacedDigit()
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.bottom, 3)
    }

    private func headerLine(_ d: DayKey, _ kcal: Double, _ target: Double) -> some View {
        Group {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Days.shortWeekday(d)).font(.system(size: size.weekday, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                dayNumber(d)
                Spacer(minLength: 4)
                if kcal > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Fmt.n0(kcal)).appFont(.headerKcal)
                            .foregroundStyle(Threshold.dayColor(kcal, target: target, otherwise: .textPrimary))
                        Text("kcal").font(.system(size: size.headerUnit)).foregroundStyle(Color.textSecondary)
                    }
                } else {
                    Text("—").appFont(.headerKcal).foregroundStyle(Color.textTertiary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.bottom, 3)
        }
    }

    /// Barre de 3 pt sur toute la largeur de la colonne, sans coins arrondis : kcal / objectif, plafonné à 100 %.
    private func gauge(_ kcal: Double, _ target: Double, belowColor: Color) -> some View {
        let ratio = target > 0 ? min(max(kcal / target, 0), 1) : 0
        return Color.hairline
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Threshold.dayColor(kcal, target: target, otherwise: belowColor)
                        .frame(width: g.size.width * ratio)
                }
            }
    }

    /// Bande au-dessus d'une ligne de repas, avec le nom du repas dans chaque colonne (en discret) :
    /// on sait toujours quel repas on regarde, où qu'on soit dans la grille.
    private func band(_ d: DayKey, slot s: Meal) -> some View {
        Color.appBackground
            .overlay(dayBackground(d))
            .frame(width: colWidth, height: size.band)
            .overlay(alignment: .topLeading) {
                // Vue d'ensemble : le nom du repas dans la première colonne seulement, la rangée se lit d'un trait.
                if !overview || d == days.first {
                    Text(overview ? s.shortName : s.name).appFont(.mealBand).foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                        .padding(.top, 7).padding(.horizontal, overview ? 5 : 9)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Vue d'ensemble : une mini-tuile avec les kcal du repas et un point par plat (ambre pour un repas libre).
    /// Toucher ouvre le jour. Case vide : rien, la colonne reste lisible d'un coup d'œil.
    private func overviewCell(day d: DayKey, slot s: Meal) -> some View {
        let list = index.entries(on: d, meal: s)
        let kcal = list.map(\.totals.kcal).reduce(0, +)
        return Button { openDay(d) } label: {
            VStack(spacing: 0) {
                if !list.isEmpty {
                    VStack(spacing: 5) {
                        Text(Fmt.n0(kcal)).font(.system(size: size.overviewKcal, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(Color.textPrimary)
                        HStack(spacing: 3) {
                            ForEach(list.prefix(4)) { e in
                                Circle().fill(e.isFree ? Color.freeMeal : Color.textTertiary).frame(width: 5, height: 5)
                            }
                            if list.count > 4 {
                                Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.gridCell, in: .rect(cornerRadius: Radius.gridCell - 4))
                    .overlay(RoundedRectangle(cornerRadius: Radius.gridCell - 4).stroke(Color.gridCellBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 3).padding(.bottom, 6)
            .frame(width: colWidth, height: size.overviewRow, alignment: .top)
            .background(dayBackground(d))
            .background(Color.appBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(list.isEmpty ? "\(Days.weekday(d)) \(Days.dayNumber(d)), \(s.name), rien de prévu"
                            : "\(Days.weekday(d)) \(Days.dayNumber(d)), \(s.name), \(list.count) plat\(list.count > 1 ? "s" : ""), \(Fmt.n0(kcal)) kilocalories")
        .accessibilityHint("Ouvrir le jour")
        .accessibilityIdentifier("cell-\(days.firstIndex(of: d) ?? -1)-\(s.rawValue)")
    }

    /// `measuring` : à sa hauteur idéale, pour que la grille calcule la hauteur de la ligne.
    private func cell(day d: DayKey, slot s: Meal, measuring: Bool = false) -> some View {
        let ref = SlotRef(date: d, meal: s)
        let list = index.entries(on: d, meal: s)
        let lone = list.filter { $0.ingredient != nil }
        let folded = lone.count >= groupFrom && !unfolded.contains(ref)
        return VStack(alignment: .leading, spacing: 6) {
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(list) { e in
                        if e.ingredient == nil || lone.count < groupFrom {
                            entryTile(e, day: d, slot: s)
                        } else if e.persistentModelID == lone.first?.persistentModelID {
                            // Les ingrédients seuls, regroupés à la place du premier : toucher déplie ou replie.
                            groupTile(lone, ref: ref, folded: folded, day: d, slot: s)
                        }
                    }
                }
                // Tuiles à leur hauteur naturelle : sinon la case partage sa hauteur avec le « + » extensible,
                // et les noms seraient tronqués à une ligne.
                .fixedSize(horizontal: false, vertical: true)
            }
            Button { add(d, s) } label: {
                Image(systemName: "plus").font(.system(size: size.plus, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: size.plusZone)
                    // La zone « + » occupe aussi la place laissée libre par une case voisine plus haute.
                    .frame(maxHeight: measuring ? nil : .infinity, alignment: .top)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter un plat : \(Days.longLabel(d)), \(s.name.lowercased())")
        }
        .padding(.horizontal, 6)
        .frame(width: colWidth, alignment: .topLeading)
        .frame(maxHeight: measuring ? nil : .infinity, alignment: .topLeading)
        .background(dropTarget == SlotRef(date: d, meal: s) ? Color.accentColor.opacity(0.14) : .clear)
        .background(dayBackground(d))
        .background(Color.appBackground)
        .sensoryFeedback(.success, trigger: dropCount)
        .accessibilityElement(children: .contain)
        // Index dans la grille (0 = premier jour affiché), pour les tests d'interface.
        .accessibilityIdentifier("cell-\(days.firstIndex(of: d) ?? -1)-\(s.rawValue)")
    }

    /// `grouped` : ligne d'un regroupement déplié, dans la carte du groupe plutôt que dans sa propre tuile.
    private func entryTile(_ e: PlanEntry, day d: DayKey, slot s: Meal, grouped: Bool = false) -> some View {
        Button { openDay(d) } label: {
            Group {
                if grouped {
                    tileContent(e)
                        .padding(EdgeInsets(top: 7, leading: 9, bottom: 8, trailing: 9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gridCell)
                } else {
                    tileContent(e).gridTile(freeMeal: e.isFree)
                }
            }
            .contentShape(.contextMenuPreview, .rect(cornerRadius: grouped ? 0 : Radius.gridCell))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Days.weekday(d)) \(Days.dayNumber(d)), \(s.name), \(e.title), \(e.isFree ? "repas libre, environ " : "")\(Fmt.n0(e.totals.kcal)) kilocalories")
        .accessibilityIdentifier("entry-\(e.title)")
        // Appui long : doigt immobile → menu ; doigt qui bouge → le plat se détache.
        // Le déposer ailleurs le duplique (« même petit-déj demain ») ; déplacer passe par le menu.
        .onDrag {
            drag.uid = e.uid
            return NSItemProvider(object: e.uid as NSString)
        } preview: { chipPreview(e) }
        .contextMenu {
            Button("Ouvrir \(Days.longLabel(d))", systemImage: "calendar") { openDay(d) }
            if let r = e.recipe {
                Button("Voir la recette", systemImage: "fork.knife") { viewingRecipe = RecipeEditTarget(recipe: r) }
                if r.byPiece {
                    Button("Modifier le nombre", systemImage: "number") { dishEdit = .pieces(e) }
                }
            } else if let g = e.ingredient {
                Button("Voir l'ingrédient", systemImage: "leaf") { viewingIngredient = IngredientEditTarget(ingredient: g) }
            } else if e.isFree {
                Button("Modifier le repas libre", systemImage: "pencil") { dishEdit = .freeMeal(e) }
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

    /// Une seule carte « 4 ingrédients · 240 kcal » ; dépliée, elle s'agrandit vers le bas et liste chaque ingrédient,
    /// qui garde son toucher, son menu et son glisser.
    private func groupTile(_ lone: [PlanEntry], ref: SlotRef, folded: Bool, day d: DayKey, slot s: Meal) -> some View {
        let kcal = lone.map(\.totals.kcal).reduce(0, +)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if folded { unfolded.insert(ref) } else { unfolded.remove(ref) }
                }
            } label: {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Même taille que les noms de plats, quel que soit le nombre : pas de rétrécissement,
                        // retour à la ligne si besoin.
                        Text("\(lone.count) ingrédients")
                            .font(.system(size: size.tileName, weight: .semibold)).lineSpacing(size.tileLeading)
                            .monospacedDigit()
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(Fmt.n0(kcal)) kcal")
                            .font(.system(size: size.tileMeta)).foregroundStyle(Color.textSecondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: size.tileMeta, weight: .semibold)).foregroundStyle(Color.accentColor)
                        .rotationEffect(.degrees(folded ? 0 : 180))
                        .padding(.top, 2)
                }
                .padding(EdgeInsets(top: 8, leading: 9, bottom: 9, trailing: 9))
                .background(Color.gridCell)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contentShape(.contextMenuPreview, .rect(cornerRadius: Radius.gridCell))
            .contextMenu {
                Button("Ouvrir \(Days.longLabel(d))", systemImage: "calendar") { openDay(d) }
                Button(LoneToRecipe.title(lone.count), systemImage: LoneToRecipe.icon) {
                    savingLone = LoneToRecipe(entries: lone)
                }
            }
            .accessibilityLabel(folded ? "\(lone.count) ingrédients seuls, \(Fmt.n0(kcal)) kcal" : "Replier les \(lone.count) ingrédients")
            .accessibilityHint(folded ? "Afficher chaque ingrédient" : "")

            // Toujours présentes, rognées à une hauteur nulle quand c'est replié : seule la hauteur s'anime,
            // la carte se déroule vers le bas au lieu de faire glisser des tuiles depuis son haut.
            VStack(spacing: 0) {
                ForEach(lone) { e in
                    Color.gridCellBorder.frame(height: 1).padding(.horizontal, 9).background(Color.gridCell)
                    entryTile(e, day: d, slot: s, grouped: true)
                }
            }
            .frame(height: folded ? 0 : nil, alignment: .top)
            .clipped()
            .opacity(folded ? 0 : 1)
            .allowsHitTesting(!folded)
            .accessibilityHidden(folded)
        }
        .gridCard()
    }

    /// Plat glissé lâché sur une case : copié à la fin de la case.
    private func dropped(on d: DayKey, slot s: Meal) {
        guard let uid = drag.uid, let e = index.entry(uid: uid) else { return }
        drag.uid = nil
        // Reposé sur sa propre case : rien à faire.
        guard e.date != d || e.meal != s else { return }
        duplicate(e, day: d, slot: s)
    }

    // Sans `withAnimation` : c'est la grille qui anime la hauteur des lignes (voir `WeekGrid.update`).
    private func move(_ e: PlanEntry, day: DayKey, slot: Meal) {
        PlanActions.move(e, date: day, slot: slot, in: context)
        dropCount += 1
    }

    private func duplicate(_ e: PlanEntry, day: DayKey, slot: Meal) {
        PlanActions.duplicate(e, date: day, slot: slot, in: context)
        dropCount += 1
    }

    /// Pour les sous-menus Copier / Déplacer : d'hier aux deux semaines à venir (au moins la semaine qui suit `day`),
    /// sauf `day`. Les jours passés de la fenêtre n'y sont pas : on planifie vers l'avant.
    @ViewBuilder
    private func dayButtons(except day: DayKey, action: @escaping (DayKey) -> Void) -> some View {
        let start = Days.adding(-1, to: today)
        let end = max(Days.adding(13, to: today), Days.adding(7, to: day))
        ForEach(Days.range(from: start, count: Days.distance(from: start, to: end) + 1).filter { $0 != day }, id: \.self) { other in
            Button { action(other) } label: {
                Text(Days.longLabel(other))
                if let r = Days.relative(other, today: today) { Text(r.prefix(1).uppercased() + r.dropFirst()) }
            }
        }
    }

    /// Aperçu du plat pendant le glisser.
    private func chipPreview(_ e: PlanEntry) -> some View {
        tileContent(e)
            .gridTile(freeMeal: e.isFree)
            .frame(width: colWidth - 12)
    }

    /// Nom du plat sur 3 lignes au plus, puis « 636 kcal », « 636 kcal · ×1,2 », ou « 150 g · 165 kcal » pour un ingrédient seul.
    private func tileContent(_ e: PlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Repas libre : petite icône ambre devant le nom.
            (e.isFree ? Text("\(Text(Image(systemName: FreeMealStyle.icon)).foregroundStyle(Color.freeMeal)) \(e.title)") : Text(e.title))
                .font(.system(size: size.tileName, weight: .semibold)).lineSpacing(size.tileLeading)
                .lineLimit(3).multilineTextAlignment(.leading)
                .foregroundStyle(Color.textPrimary)
            chipDetail(e).font(.system(size: size.tileMeta)).foregroundStyle(Color.textSecondary).monospacedDigit()
        }
    }

    private func chipDetail(_ e: PlanEntry) -> Text {
        let kcal = "\(Fmt.n0(e.totals.kcal)) kcal"
        switch e.kind {
        case .ingredient(let g, let q):
            return Text(Fmt.cook(q * e.x, unit: g.unit) + " · " + kcal)
        case .freeMeal(let m):
            return Text(FreeMealStyle.kcal(m)).foregroundStyle(Color.freeMeal)
        case .recipe(let r) where r.byPiece:
            // À la pièce : toujours le nombre (« 1 300 kcal · 2 pièces »).
            return Text("\(kcal) · \(Text(Fmt.pieces(e.x)).fontWeight(.semibold).foregroundStyle(Color.accentColor))")
        case .recipe, .empty:
            guard e.x != 1 else { return Text(kcal) }
            return Text("\(kcal) · \(Text(Fmt.x(e.x)).fontWeight(.semibold).foregroundStyle(Color.accentColor))")
        }
    }
}

/// Tailles de la grille, qui suivent la taille de texte choisie.
private struct GridSizes: DynamicProperty {
    @ScaledMetric(relativeTo: .subheadline) var statsUnit: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) var statsCount: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) var header: CGFloat = 38
    @ScaledMetric(relativeTo: .subheadline) var weekday: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) var headerUnit: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) var band: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) var tileName: CGFloat = 14
    /// Interligne 18 pour le nom en 14.
    @ScaledMetric(relativeTo: .subheadline) var tileLeading: CGFloat = 1.3
    @ScaledMetric(relativeTo: .caption) var tileMeta: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) var plus: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) var plusZone: CGFloat = 26
    /// Vue d'ensemble : en-tête sur trois lignes, rangée de repas de hauteur fixe, kcal de la mini-tuile.
    @ScaledMetric(relativeTo: .subheadline) var overviewHeader: CGFloat = 58
    @ScaledMetric(relativeTo: .subheadline) var overviewRow: CGFloat = 52
    @ScaledMetric(relativeTo: .caption) var overviewKcal: CGFloat = 12
}

/// Plat glissé depuis la grille, retenu dès le départ du geste : le dépôt le copie sans attendre que le système
/// livre le contenu glissé. Une simple référence, pas un état observé : la retenir ne redessine rien.
final class DragSource {
    var uid: String?
}

/// Pastille du tirer : le bleu la remplit depuis le côté tiré à mesure qu'on approche du seuil ; pleine (et un peu
/// plus grande) au seuil. Seule à lire l'avancée, elle est la seule redessinée à chaque image.
private struct PullBadge: View {
    var text: String
    var pull: WeekPull
    var meter: PullMeter

    var body: some View {
        let anchor: UnitPoint = pull.forward ? .trailing : .leading
        label(Color.textSecondary)
            .background(Color.surface)
            // Partie remplie : texte blanc sur bleu, découpée à l'avancée du tirer.
            .overlay {
                label(Color.onAccent)
                    .background(Color.accentColor)
                    .mask { Rectangle().scaleEffect(x: meter.progress, anchor: anchor) }
            }
            .clipShape(.capsule)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .scaleEffect(pull.armed ? 1.05 : 1)
    }

    private func label(_ color: Color) -> some View {
        HStack(spacing: 6) {
            if !pull.forward { Image(systemName: "chevron.left") }
            Text(text)
            if pull.forward { Image(systemName: "chevron.right") }
        }
        .font(.subheadline.weight(.semibold)).monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
