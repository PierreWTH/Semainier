import SwiftData
import SwiftUI
import UIKit

struct DayView: View {
    @Binding var day: DayKey
    /// Semaine affichée dans le bandeau, signalée au planning (bouton du jour). Le bandeau défile seul,
    /// sans changer `day`.
    @Binding var stripWeek: DayKey?
    /// Change quand le bandeau doit revenir sur la semaine du jour affiché (bouton du jour).
    var recenter: Int
    var index: PlanIndex
    var ns: Namespace.ID
    var add: (Repas) -> Void
    /// Carte total sortie de l'écran : la bulle du haut prend alors le relais avec le total du jour.
    @Binding var totalCardHidden: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(Toast.self) private var toast
    @Environment(\.modelContext) private var context
    @State private var expanded: Set<PersistentIdentifier> = []
    @State private var edition: EditionPlat?
    @State private var savingLone: LoneToRecipe?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Kcal sous la date, dans le bandeau des jours.
    @ScaledMetric(relativeTo: .caption2) private var kcalSize: CGFloat = 10.5
    private let size = TaillesRepas()
    /// Semaine affichée dans le bandeau, propre à cette vue : elle repart de la semaine du jour à chaque ouverture.
    /// Partagée avec le planning, elle pouvait recevoir, à la fermeture du bandeau, la première semaine de sa plage
    /// (un an plus tôt), qui revenait à l'ouverture suivante.
    @State private var shownWeek: DayKey?

    var body: some View {
        let dayEntries = index.entries(on: day)
        let t = dayEntries.map(\.totals).sum
        let target = settings.targetKcal

        VStack(alignment: .leading, spacing: 0) {
            strip(target)
                .padding(.bottom, 12)

            totalCard(t, target)
                .onScrollVisibilityChange(threshold: 0.2) { visible in
                    withAnimation(.snappy) { totalCardHidden = !visible }
                }

            if dayEntries.isEmpty {
                VStack(spacing: 2) {
                    Text("Rien de prévu pour \(Days.weekday(day).lowercased()).")
                    Text("Ajouter un plat, ou copier une journée depuis la semaine.")
                }
                .font(.subheadline).foregroundStyle(Color.texte2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Repas.allCases) { s in
                    slotSection(s, dayEntries.filter { $0.repas == s })
                }
            }
            .padding(.top, 24)
        }
        .contentShape(.rect)
        .editionPlat($edition)
        .saveLoneAsRecipe($savingLone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jour-\(day)")
        .sensoryFeedback(.selection, trigger: day)
    }

    /// Carte total en verre : kcal du jour sur l'objectif, puis les trois macros.
    private func totalCard(_ t: Macros, _ target: Double) -> some View {
        let over = Seuil.depasse(t.kcal, objectif: target)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.n0(t.kcal)).police(.totalCarte)
                    .foregroundStyle(t.kcal == 0 ? Color.texte3 : over ? Color.depassement : Color.texte)
                    .contentTransition(.numericText(value: t.kcal))
                Text("/ \(Fmt.n0(target)) kcal").font(.system(size: size.totalUnit)).foregroundStyle(Color.texte2)
            }
            .monospacedDigit()
            BarreObjectif(valeur: t.kcal, objectif: target, couleur: .remplissageKcal, piste: .pisteCarteTotal, hauteur: 6)
                .animation(.snappy, value: t.kcal)
                .padding(.top, 8)
            MacroBars(totals: t, targets: settings.targets)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .carteTotal()
    }

    /// Début de la semaine d'aujourd'hui (lundi ou aujourd'hui, selon le réglage).
    private var homeWeek: DayKey { Days.weekStart(Days.today, fromMonday: settings.weekFromMonday) }

    /// Début de la semaine du bandeau qui contient `d`.
    private func week(of d: DayKey) -> DayKey { Days.weekStart(containing: d, home: homeWeek) }

    /// Bandeau qui défile par semaine entière, un an avant et après la semaine d'aujourd'hui.
    /// Toucher une puce ouvre ce jour ; faire défiler seul ne change pas le jour affiché.
    private func strip(_ target: Double) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    // Identifiées par leur premier jour dans le ForEach lui-même : un `.id()` posé sur la page n'existe
                    // que pour les pages déjà construites, et l'iPhone ne trouvait pas la semaine du jour.
                    ForEach((-52...52).map { Days.adding($0 * 7, to: homeWeek) }, id: \.self) { start in
                        Grid(horizontalSpacing: 5) {
                            GridRow {
                                ForEach(Days.range(from: start, count: 7), id: \.self) { d in stripChip(d, target) }
                            }
                        }
                        // Marge d'écran dans chaque page : les semaines voisines arrivent depuis le bord de l'écran.
                        .padding(.horizontal, Espace.marge)
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            // Jamais vide, dès la première mise en page : sans semaine choisie, celle du jour affiché (une ancre
            // `defaultScrollAnchor` ralentissait le passage à la vue Jour). Sert aussi à suivre le défilement du doigt.
            .scrollPosition(id: Binding(get: { shownWeek ?? week(of: day) }, set: { if let w = $0 { shownWeek = w } }))
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Espace.marge)
            // Placement explicite dès que la largeur est connue (mise en page réelle des pages) : la liaison seule
            // peut croire le bandeau en place alors qu'il s'est posé sur la première page.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                guard width > 0 else { return }
                let w = shownWeek ?? week(of: day)
                DispatchQueue.main.async { proxy.scrollTo(w) }
            }
            .onChange(of: shownWeek) { stripWeek = shownWeek }
            // Jour changé ailleurs, ou bouton du jour : le bandeau rejoint la semaine du jour affiché.
            .onChange(of: day) { showDayWeek(proxy) }
            .onChange(of: recenter) { showDayWeek(proxy) }
        }
    }

    private func showDayWeek(_ proxy: ScrollViewProxy) {
        let w = week(of: day)
        withAnimation(.snappy) {
            shownWeek = w
            proxy.scrollTo(w)
        }
    }

    private func stripChip(_ d: DayKey, _ target: Double) -> some View {
        let k = index.totals(on: d).kcal
        let on = d == day
        return Button { withAnimation(.modeSwitch) { day = d } } label: {
            VStack(spacing: 2) {
                Text(Days.shortWeekday(d)).police(.jourBandeau)
                    .opacity(0.85)
                Text(Days.dayNumber(d)).police(.dateBandeau)
                if !typeSize.isAccessibilitySize {
                    Text(k > 0 ? Fmt.n0(k) : "—").font(.system(size: kcalSize)).monospacedDigit()
                        .foregroundStyle(on ? Color.surAccent : Color.texte2)
                }
                // Sur la puce bleue, piste opaque : la couleur de validation reste lisible, en clair comme en sombre.
                BarreObjectif(valeur: k, objectif: target, couleur: Seuil.couleurJour(k, objectif: target, sinon: .texte2),
                              piste: on ? .surface : .surface2, hauteur: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            // Réduction automatique (coûteuse) seulement quand le texte est agrandi.
            .lineLimit(1).minimumScaleFactor(typeSize > .large ? 0.7 : 1)
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(on ? Color.surAccent : Color.texte)
            .opacity(d < Days.today && !on ? 0.6 : 1)
            .background {
                // La puce bleue glisse d'un jour à l'autre, et vient du tampon de date touché dans la semaine.
                if on {
                    RoundedRectangle(cornerRadius: Arrondi.puceJour).fill(Color.accentColor)
                        .matchedGeometryEffect(id: "jour", in: ns)
                } else {
                    RoundedRectangle(cornerRadius: Arrondi.puceJour).fill(Color.surface)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Days.longLabel(d))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Un repas : en-tête sur deux lignes, puis une seule carte qui contient ses plats et la ligne « + Ajouter ».
    private func slotSection(_ s: Repas, _ list: [PlanEntry]) -> some View {
        let valid = list.filter(\.isValid)
        return VStack(alignment: .leading, spacing: 8) {
            slotHeader(s, valid)

            VStack(alignment: .leading, spacing: 0) {
                let lone = valid.filter { $0.ingredient != nil }
                ForEach(valid) { e in
                    entryRow(e, lone: lone)
                    Rectangle().fill(Color.filetCarte).frame(height: 1).padding(.leading, 14)
                }
                Button { add(s) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: size.addIcon, weight: .semibold))
                        Text("Ajouter").font(.system(size: size.add, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, minHeight: size.addRow, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter un plat")
            }
            .background(Color.surface, in: .rect(cornerRadius: 14))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    /// « PETIT-DÉJEUNER ……… 636 kcal », puis « G 86 · P 25 · L 20 g » et la barre de répartition.
    private func slotHeader(_ s: Repas, _ list: [PlanEntry]) -> some View {
        let m = list.map(\.totals).sum
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.nom)
                    .font(.system(size: size.slotName, weight: .semibold))
                    .tracking(size.slotName * 0.06)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.texte2)
                Spacer()
                if m.kcal > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(Fmt.n0(m.kcal)).fontWeight(.semibold).foregroundStyle(Color.texte)
                        Text("kcal").foregroundStyle(Color.texte2)
                    }
                    .font(.system(size: size.slotKcal))
                    .monospacedDigit()
                } else {
                    Text("—").font(.system(size: size.slotKcal)).foregroundStyle(Color.texte3)
                }
            }
            if !list.isEmpty {
                // Récap du repas : répartition des kcal entre G / P / L.
                HStack(spacing: 10) {
                    MacroLine(m: m, unit: " g")
                        .font(.system(size: size.slotMacros)).foregroundStyle(Color.texte2)
                        .lineLimit(1).fixedSize()
                    BarreRepartition(g: m.c, p: m.p, l: m.f, hauteur: 3)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    /// `lone` : les ingrédients seuls du repas, qu'un appui long sur l'un d'eux propose d'enregistrer comme recette.
    private func entryRow(_ e: PlanEntry, lone: [PlanEntry]) -> some View {
        let open = expanded.contains(e.persistentModelID)
        let t = e.totals
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    if e.isFree {
                        edition = .libre(e)
                    } else if e.ingredient != nil {
                        edition = .quantite(e)
                    } else {
                        withAnimation(.snappy) {
                            if open { expanded.remove(e.persistentModelID) } else { expanded.insert(e.persistentModelID) }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if e.isFree {
                                Image(systemName: FreeMealStyle.icon)
                                    .font(.system(size: size.dishMeta, weight: .semibold))
                                    .foregroundStyle(Color.libre)
                                    .accessibilityHidden(true)
                            }
                            Text(e.title).lineLimit(1).truncationMode(.tail)
                            // À la pièce : le nombre est dans la pastille à droite, pas en « ×2 ».
                            if let r = e.recipe, !r.byPiece, e.x != 1 {
                                Text(Fmt.x(e.x)).foregroundStyle(Color.accentColor).fixedSize()
                            }
                            // Plat (recette) : chevron pour montrer qu'il se déplie. Ingrédient seul : rien.
                            if e.recipe != nil {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: size.chevron, weight: .bold))
                                    .foregroundStyle(Color.texte3)
                                    .rotationEffect(.degrees(open ? 180 : 0))
                                    .accessibilityHidden(true)
                            }
                        }
                        .font(.system(size: size.dishName, weight: .semibold))
                        Group {
                            if let m = e.free {
                                // « ≈ 1 200 kcal · estimé », ou les macros quand elles sont précisées.
                                Text("\(Text(FreeMealStyle.kcal(m)).foregroundStyle(Color.libre)) · \(m.hasMacros ? MacroLine.text(t) : Text("estimé"))")
                            } else if let g = e.ingredient {
                                Text("\(Fmt.cook(e.qty * e.x, unit: g.unit)) · \(Fmt.n0(t.kcal)) kcal · \(MacroLine.text(t))")
                            } else {
                                Text("\(Fmt.n0(t.kcal)) kcal · \(MacroLine.text(t))")
                            }
                        }
                        .font(.system(size: size.dishMeta)).foregroundStyle(Color.texte2)
                        .lineLimit(1)
                    }
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(e.isFree ? "Modifier le repas libre" : e.ingredient != nil ? "Modifier la quantité" : open ? "Masquer les ingrédients" : "Afficher les ingrédients")

                // Plat à la pièce : « 2 pièces » en pastille, toucher pour changer le nombre.
                if let r = e.recipe, r.byPiece {
                    Button { edition = .pieces(e) } label: { QuantityChip(text: Fmt.pieces(e.x)) }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .accessibilityLabel("\(Fmt.pieces(e.x)), modifier le nombre")
                }

                Button("Retirer \(e.title)", systemImage: "xmark") {
                    withAnimation(.snappy) { context.delete(e) }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: size.cross, weight: .bold))
                .foregroundStyle(Color.texte3)
                .frame(width: 40, height: 40)
                .contentShape(.rect.inset(by: -2))
                .buttonStyle(.borderless)
            }
            .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 2))
            // Repas libre : ligne sur fond sable, pour le reconnaître dans la carte du repas.
            // Rectangle explicite : un simple fond reprendrait les coins arrondis de la carte.
            // Toujours présent, pour que l'aperçu de l'appui long garde le fond de la ligne.
            .background { Rectangle().fill(e.isFree ? Color.libreFond : Color.surface) }
            .contextMenu {
                if e.ingredient != nil && lone.count >= 2 {
                    Button(LoneToRecipe.title(lone.count), systemImage: LoneToRecipe.icon) {
                        savingLone = LoneToRecipe(entries: lone)
                    }
                }
            }

            if open, let r = e.recipe {
                let items = r.sortedItems.filter { $0.ingredient != nil }
                VStack(spacing: 0) {
                    ForEach(items) { it in
                        if let g = it.ingredient {
                            let q = e.qty(for: it) * e.x
                            // Toute la ligne ouvre la saisie ; la quantité en pastille montre que c'est modifiable.
                            Button { edition = .ligne(e, it) } label: {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(g.name).font(.system(size: size.ingName))
                                        let m = g.macros(qty: q)
                                        Text("\(Fmt.n0(m.kcal)) kcal · \(MacroLine.text(m))")
                                            .font(.system(size: size.ingMeta)).foregroundStyle(Color.texte2)
                                            .monospacedDigit()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer(minLength: 8)
                                    QuantityChip(text: Fmt.cook(q, unit: g.unit), modified: e.isOverridden(it))
                                }
                                .frame(minHeight: 32)
                                .padding(EdgeInsets(top: 6, leading: 26, bottom: 6, trailing: 10))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Modifier la quantité pour ce plat")
                            if it.persistentModelID != items.last?.persistentModelID {
                                Rectangle().fill(Color.filetCarte).frame(height: 1).padding(.leading, 26)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .background { Rectangle().fill(Color.fondDeplie) }
                .overlay(alignment: .top) { Color.filetCarte.frame(height: 1) }
                // Fondu seul : la carte s'agrandit ou se réduit, la liste ne glisse plus par-dessus le titre.
                .transition(.opacity)
            }
        }
    }
}

/// Tailles de la liste des repas (vue Jour), qui suivent la taille de texte dynamique.
private struct TaillesRepas: DynamicProperty {
    @ScaledMetric(relativeTo: .caption) var slotName: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) var slotKcal: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) var slotMacros: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) var dishName: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) var dishMeta: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) var cross: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) var chevron: CGFloat = 10
    /// « / 2 600 kcal » à côté du total de la carte.
    @ScaledMetric(relativeTo: .subheadline) var totalUnit: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) var ingName: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) var ingMeta: CGFloat = 11.5
    @ScaledMetric(relativeTo: .subheadline) var add: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) var addIcon: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) var addRow: CGFloat = 38
}
