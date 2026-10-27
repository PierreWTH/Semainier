import SwiftData
import SwiftUI

/// Une case du planning : un repas d'un jour.
struct SlotRef: Identifiable, Hashable {
    var date: DayKey
    var meal: Meal
    var id: Int { date * 10 + meal.rawValue }
}

struct PlanningView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    /// Change au passage de minuit (voir `SuiviDuJour`) : relu ici pour redessiner les dates.
    @Environment(\.currentDay) private var currentDay
    @Query private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]
    // État local (animable) ; recopié dans les préférences pour s'en souvenir au prochain lancement.
    // Une écriture directe dans @AppStorage n'est pas animée.
    @State private var mode = UserDefaults.standard.string(forKey: Prefs.planningMode).flatMap(PlanningMode.init) ?? .week
    /// Jour sélectionné (vue jour, pastille de la semaine).
    @State private var day = Days.today
    /// Semaine affichée dans la grille, par son premier jour, quand ce n'est pas celle d'aujourd'hui (`homeStart`).
    @State private var weekAnchor: DayKey?
    @State private var adding: SlotRef?
    @State private var newRecipe = false
    @State private var copying = false
    @State private var confirmClear = false
    /// Vue Jour : carte total hors de l'écran (la bulle du haut montre alors le total du jour).
    @State private var dayCardHidden = false
    /// Hauteur visible de la page : en vue Semaine, la grille (qui défile elle-même) remplit ce qui reste.
    @State private var visibleHeight: CGFloat = 0
    @State private var pagePosition = ScrollPosition(edge: .top)
    /// Vue Semaine : la colonne d'aujourd'hui est à l'écran.
    @State private var todayOnScreen = true
    /// Incrémenté par le bouton du jour : la grille revient sur aujourd'hui même si ses jours ne changent pas.
    @State private var recenter = 0
    /// Relie la colonne touchée dans la semaine à la pastille du jour (animation de bascule).
    @Namespace private var dayNS

    private var weekStart: DayKey { weekAnchor ?? homeStart }
    private var weekDays: [DayKey] { Days.range(from: weekStart, count: 7) }

    /// Vue Semaine en vue d'ensemble (pincer, ou menu ⋯), retenue d'un lancement à l'autre.
    @State private var overview = UserDefaults.standard.bool(forKey: Prefs.overview)

    /// Vue Jour : semaine affichée dans le bandeau des jours (il défile sans changer de jour).
    @State private var stripWeek: DayKey?

    /// Semaine voisine, après un tirer au bord de la grille.
    private func shiftWeek(forward: Bool) {
        let start = Days.adding(forward ? 7 : -7, to: weekStart)
        weekAnchor = start == homeStart ? nil : start
    }

    /// Début de la semaine d'aujourd'hui : aujourd'hui, ou le lundi de cette semaine (réglage).
    private var homeStart: DayKey { Days.weekStart(Days.today, fromMonday: settings.weekFromMonday) }

    /// Bouton du jour (« Ven 23 ») : revient sur aujourd'hui et referme les autres semaines.
    /// Il apparaît quand aujourd'hui n'est pas à l'écran : autre jour choisi, colonne d'aujourd'hui sortie de la grille
    /// (ou autre semaine), ou autre semaine dans le bandeau de la vue Jour.
    private var awayFromToday: Bool {
        day != Days.today || (mode != .day && !todayOnScreen)
            || (mode == .day && stripWeek.map { $0 != homeStart } ?? false)
    }

    private func backToToday() {
        withAnimation(.modeSwitch) {
            day = Days.today
            weekAnchor = nil
        }
        recenter += 1
    }

    /// La grille montre la semaine du jour choisi (jour changé en vue Jour).
    private func keepDayInWeek() {
        let start = weekStart(of: day)
        weekAnchor = start == homeStart ? nil : start
    }

    /// Rien à planifier tant qu'il n'y a ni recette ni ingrédient (ni plat, des repas libres seuls restant possibles).
    private var isEmpty: Bool {
        recipes.isEmpty && ingredients.isEmpty && context.fetchCountOrLog(FetchDescriptor<PlanEntry>()) == 0
    }

    /// Début de la semaine (au sens du réglage) qui contient `d`.
    private func weekStart(of d: DayKey) -> DayKey { Days.weekStart(containing: d, home: homeStart) }

    /// Jours chargés depuis la base : la semaine de la grille, celle du bandeau et celle du jour choisi, avec deux
    /// semaines de marge de chaque côté (semaine voisine tirée, bandeau qui défile). Tout l'historique coûtait une
    /// requête complète à chaque modification.
    private var window: Range<DayKey> {
        let starts = [weekStart, stripWeek ?? weekStart, weekStart(of: day)]
        return Days.adding(-14, to: starts.min()!)..<Days.adding(21, to: starts.max()!)
    }

    var body: some View {
        PlanEntriesQuery(window) { entries in content(PlanIndex(entries)) }
    }

    private func content(_ index: PlanIndex) -> some View {
        let dayEmpty = index.isEmpty(day)
        return NavigationStack {
            Group {
                if isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            ContentUnavailableView {
                                Label("Le planning attend ses premiers plats", systemImage: "calendar")
                            } description: {
                                Text("Créer d'abord des recettes ou des ingrédients, puis les placer sur chaque jour.")
                            } actions: {
                                Button("Créer une recette") { newRecipe = true }.buttonStyle(.glassProminent)
                            }
                        }
                        .padding()
                    }
                } else {
                    // Un seul défilement pour les deux vues : la bascule s'anime et le grand titre reste en place.
                    ScrollView {
                        VStack(alignment: .leading, spacing: mode == .day ? 16 : 12) {
                            ModePicker(mode: $mode)
                            if mode == .day {
                                DayView(day: $day, stripWeek: $stripWeek, recenter: recenter, index: index, ns: dayNS,
                                        add: { adding = SlotRef(date: day, meal: $0) },
                                        totalCardHidden: $dayCardHidden)
                                    .transition(.modeSwitch(.offset(y: 28)))
                            } else {
                                WeekView(index: index, days: weekDays, selected: day,
                                         openDay: { d in day = d; withAnimation(.modeSwitch) { mode = .day } },
                                         add: { adding = SlotRef(date: $0, meal: $1) },
                                         shift: shiftWeek(forward:), recenter: recenter,
                                         todayVisible: { on in if todayOnScreen != on { todayOnScreen = on } },
                                         overview: $overview)
                                    // Recréée quand le réglage change, pour se recaler sur le jour choisi.
                                    .id(settings.weekFromMonday)
                                    .transition(.modeSwitch(.scale(scale: 0.97, anchor: .top)))
                            }
                        }
                        .padding(.horizontal).padding(.bottom)
                        // Le titre maison de la barre a déjà sa marge, comme les grands titres système.
                        // Semaine : la page tient dans l'écran, c'est la grille qui défile (dans les deux sens).
                        .frame(height: mode == .day || visibleHeight == 0 ? nil : visibleHeight, alignment: .top)
                    }
                    .scrollPosition($pagePosition)
                    .scrollDisabled(mode != .day)
                    // Zone visible : déjà sans la barre du haut ni la barre d'onglets.
                    .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, h in visibleHeight = h }
                }
            }
            .background(Color.appBackground)
            .onChange(of: mode) {
                UserDefaults.standard.set(mode.rawValue, forKey: Prefs.planningMode)
                if mode != .day {
                    pagePosition.scrollTo(edge: .top)
                    // Au retour en vue Jour, le bandeau repart de la semaine du jour affiché.
                    stripWeek = nil
                }
                dayCardHidden = false
            }
            .onChange(of: day) { keepDayInWeek() }
            // Nouveau jour : la sélection suit si elle était sur « aujourd'hui » ; un autre jour choisi reste choisi.
            .onChange(of: currentDay) { old, new in
                if day == old { day = new } else { keepDayInWeek() }
            }
            .onChange(of: overview) { UserDefaults.standard.set(overview, forKey: Prefs.overview) }
            // Réglage changé : la semaine repart de celle du jour choisi, avec le nouveau premier jour.
            .onChange(of: settings.weekFromMonday) { keepDayInWeek() }
            .navigationTitle(isEmpty ? "Planning" : mode == .day ? Days.weekday(day) : "Semaine")
            .toolbar {
                // Même en-tête pour Semaine et Jour (grand titre + précision à droite, sur la ligne de base) :
                // seul le texte change à la bascule. Un changement de type de titre (grand ↔ compact avec
                // sous-titre) faisait geler le contenu le temps de la transition de la barre, et sauter l'en-tête.
                if !isEmpty {
                    ToolbarItem(placement: .largeTitle) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(mode == .day ? Days.weekday(day) : "Semaine").font(.largeTitle.bold())
                                .contentTransition(.opacity)
                            Spacer(minLength: 8)
                            Text(mode == .day ? daySubtitle
                                 : Days.shortRangeText(weekStart, Days.adding(6, to: weekStart)))
                                .font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                                .monospacedDigit()
                                .contentTransition(.opacity)
                        }
                        .lineLimit(1)
                        // Même hauteur que le grand titre système des onglets Courses et Cuisine.
                        .padding(.top, 12)
                    }
                }
                if !isEmpty && awayFromToday {
                    ToolbarItem(placement: .topBarLeading) {
                        // La date du jour plutôt que « Aujourd'hui » : plus court, et on sait où l'on revient.
                        Button(Days.shortLabel(Days.today), action: backToToday)
                            .monospacedDigit()
                            .accessibilityLabel("Revenir à aujourd'hui, \(Days.longLabel(Days.today))")
                            .accessibilityIdentifier("today")
                    }
                }
            }
            // Jour : rien tant que la carte total est visible, puis le total du jour. Semaine : pas de bulle,
            // l'objectif est dans la ligne de moyenne.
            .appChrome(dayTotals: mode == .day && !isEmpty && dayCardHidden
                       ? index.totals(on: day) : nil) {
                if mode != .day && !isEmpty {
                    // Même bascule que le pincement, pour qui ne le connaît pas (et pour VoiceOver).
                    Button(overview ? "Vue détaillée" : "Vue d'ensemble",
                           systemImage: overview ? "rectangle.split.3x1" : "square.grid.3x3") { overview.toggle() }
                }
                if mode == .day && !isEmpty {
                    Button("Copier ce jour vers…", systemImage: "doc.on.doc") { copying = true }
                        .disabled(dayEmpty)
                    Button("Vider ce jour", systemImage: "trash", role: .destructive) { confirmClear = true }
                        .disabled(dayEmpty)
                }
            }
            .alert("Tout retirer du \(Days.longLabel(day).lowercased()) ?", isPresented: $confirmClear) {
                Button("Annuler", role: .cancel) {}
                Button("Vider", role: .destructive) {
                    withAnimation { index.entries(on: day).forEach(context.delete) }
                    toast.show("\(Days.longLabel(day)) vidé")
                }
            }
            .sheet(isPresented: $copying) { CopyDaySheet(source: day) }
            .sheet(item: $adding) { ref in RecipePickerSheet(ref: ref) }
            .sheet(isPresented: $newRecipe) { RecipeEditor(recipe: nil) }
        }
    }

    /// « aujourd'hui · 15 octobre », « 15 octobre », ou « 26 octobre 2025 » hors de l'année en cours.
    private var daySubtitle: String {
        let date = Days.dayMonth(day) + (day / 10000 != Days.today / 10000 ? " \(day / 10000)" : "")
        return [Days.relative(day), date].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Plats d'une plage de jours, passés à `content`. La requête est refaite quand la plage change.
private struct PlanEntriesQuery<Content: View>: View {
    @Query private var entries: [PlanEntry]
    let content: ([PlanEntry]) -> Content

    init(_ days: Range<DayKey>, @ViewBuilder content: @escaping ([PlanEntry]) -> Content) {
        let lo = days.lowerBound, hi = days.upperBound
        _entries = Query(filter: #Predicate { $0.date >= lo && $0.date < hi })
        self.content = content
    }

    var body: some View { content(entries) }
}

extension Animation {
    /// Bascule Semaine ↔ Jour : ressort léger.
    static let modeSwitch = Animation.spring(duration: 0.5, bounce: 0.22)
}

extension AnyTransition {
    /// L'écran entrant arrive en fondu avec `motion` ; le sortant s'efface très vite pour éviter la double image.
    static func modeSwitch(_ motion: AnyTransition) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: motion),
                    removal: .opacity.animation(.easeOut(duration: 0.12)))
    }
}

/// Bascule Semaine / Jour, en tête des deux vues.
struct ModePicker: View {
    @Binding var mode: PlanningMode

    var body: some View {
        Picker("Vue", selection: $mode.animation(.modeSwitch)) {
            Text("Semaine").tag(PlanningMode.week)
            Text("Jour").tag(PlanningMode.day)
        }
        .pickerStyle(.segmented)
    }
}
