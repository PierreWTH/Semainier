import SwiftUI
import UIKit

/// Grille Semaine en `UICollectionView` : défilement dans les deux sens, en-tête des jours figé en haut
/// par la mise en page elle-même (comme un tableur ou un agenda).
/// Une seule semaine à la fois : au bord, le rebond élastique d'iOS ; tirer au-delà d'un seuil puis lâcher
/// passe à la semaine voisine (comme « tirer pour actualiser »), avec une transition de page.
/// Le contenu (en-têtes, bandes de repas, cases) reste en SwiftUI, affiché dans les cellules.
struct WeekGrid: UIViewRepresentable {
    var days: [DayKey]
    var selected: DayKey
    /// Largeur visible de la grille (pour mesurer la ligne de moyenne et le texte d'aide).
    var width: CGFloat
    var colWidth: CGFloat
    var headerHeight: CGFloat
    var bandHeight: CGFloat
    /// Change quand une hauteur de ligne peut changer (plats, groupes dépliés, taille de texte) : on remesure.
    var layoutKey: Int
    /// Empreinte du contenu d'une case : seules les cases dont elle a changé sont remesurées.
    var cellKey: (_ day: DayKey, _ repas: Repas) -> Int
    /// Change quand il faut revenir sur le jour choisi (bouton du jour) sans que les jours changent.
    var recenter: Int
    var header: (DayKey) -> AnyView
    var band: (DayKey, Repas) -> AnyView
    /// `measuring` : version à sa hauteur idéale (pour calculer la hauteur de la ligne), sans étirement.
    var cell: (_ day: DayKey, _ repas: Repas, _ measuring: Bool) -> AnyView
    var footer: AnyView
    /// Passer à la semaine voisine : `true` la suivante, `false` la précédente.
    var shift: (_ forward: Bool) -> Void
    /// Jours visibles (au moins à moitié), à chaque changement.
    var visible: (ClosedRange<DayKey>) -> Void
    /// Un plat de la grille est en cours de glisser.
    var canDrop: () -> Bool
    /// Case survolée pendant le glisser (nil en dehors).
    var hover: (SlotRef?) -> Void
    /// Dépôt sur une case.
    var drop: (_ day: DayKey, _ repas: Repas) -> Void
    /// Tirer au-delà du bord vers la semaine voisine (nil hors de ce geste).
    var pull: (WeekPull?) -> Void = { _ in }
    /// Avancée du tirer, image par image : lue par la seule pastille, pour ne pas recalculer la vue Semaine.
    var meter = PullMeter()
    /// Pincement : `true` pour dézoomer (vue d'ensemble), `false` pour revenir au détail.
    var zoom: (_ out: Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GridCollectionView {
        let cv = GridCollectionView(frame: .zero, collectionViewLayout: WeekGridLayout())
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        // Rebond vertical en bas seulement : en haut, le défilement est arrêté net (voir `scrollViewDidScroll`),
        // pour que les en-têtes de jour, figés en haut, ne descendent jamais avec la grille.
        // Un geste défile dans un seul sens (celui où le doigt part), jamais en diagonale.
        cv.isDirectionalLockEnabled = true
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Kind.cell)
        for kind in [Kind.header, Kind.band, Kind.footer] {
            cv.register(UICollectionViewCell.self, forSupplementaryViewOfKind: kind, withReuseIdentifier: kind)
        }
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        context.coordinator.collectionView = cv
        // Le dépôt est géré ici, en UIKit, plutôt que par `onDrop` dans chaque case : le plat attrapé ne disparaît
        // plus le temps de l'animation de dépôt, et la case visée se déduit de la mise en page.
        cv.addInteraction(UIDropInteraction(delegate: context.coordinator))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched(_:)))
        // Reconnu en même temps que le défilement : sinon deux doigts qui se rapprochent partent en défilement.
        pinch.delegate = context.coordinator
        cv.addGestureRecognizer(pinch)
        return cv
    }

    func updateUIView(_ cv: GridCollectionView, context: Context) {
        context.coordinator.update(self)
    }

    enum Kind {
        static let cell = "cell", header = "header", band = "band", footer = "footer"
        static let separator = "separator"
    }

    /// Lignes de la grille : une par repas (item = jour × `rows` + repas).
    static let rows = Repas.allCases.count

    /// Dépassement du bord (dans le rebond, qui résiste de plus en plus) au-delà duquel le lâcher change de semaine :
    /// environ 150 pt de doigt. Un défilement lancé finit dans le rebond sans jamais compter : seul le doigt
    /// posé tire.
    static let pullThreshold: CGFloat = 70

    // MARK: - Coordinateur : données, mesures, bords

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIDropInteractionDelegate,
                             UIGestureRecognizerDelegate {
        weak var collectionView: GridCollectionView?
        private var parent: WeekGrid?
        /// Hauteur idéale de chaque case, par largeur de colonne (détail, vue d'ensemble), avec l'empreinte de son
        /// contenu au moment de la mesure. Partagée entre les grilles successives : revenir sur la vue Semaine, ou
        /// passer d'un niveau de zoom à l'autre, ne remesure que les cases changées.
        private static var heights: [CGFloat: [SlotRef: (key: Int, height: CGFloat)]] = [:]
        /// Jour (index) sous les doigts au pincement : la grille revient sur lui en repassant au détail.
        private var zoomDay: Int?
        /// Point entre les doigts au pincement (dans la vue qui contient la grille) : le zoom part de là.
        private var zoomPoint: CGPoint?
        /// Le pincement en cours a déjà basculé de niveau : une seule bascule par geste.
        private var zoomed = false
        /// Largeur et taille de texte (via la hauteur d'en-tête) de la dernière mesure du texte d'aide.
        private var footerFor: [CGFloat] = []
        private var lastVisible: ClosedRange<DayKey>?
        /// Case survolée signalée en dernier, pour ne prévenir SwiftUI qu'aux changements.
        private var hovered: SlotRef?
        /// Dernier état du tirer signalé, pour ne prévenir SwiftUI qu'aux changements.
        private var pulled: WeekPull?
        /// Semaine voisine demandée au lâcher : la nouvelle arrive par une transition de page dans ce sens.
        private var shifting: Bool?
        /// Page en train de tourner : la pastille reste pleine jusqu'au bout, les défilements sont ignorés.
        private var turning = false

        private var layout: WeekGridLayout? { collectionView?.collectionViewLayout as? WeekGridLayout }

        func update(_ new: WeekGrid) {
            guard let cv = collectionView, let layout else { return }
            let old = parent
            parent = new
            let daysChanged = old?.days != new.days
            let remeasure = daysChanged || old?.layoutKey != new.layoutKey || old?.colWidth != new.colWidth
                || old?.headerHeight != new.headerHeight || old?.bandHeight != new.bandHeight || old?.width != new.width

            if remeasure {
                layout.dayCount = new.days.count
                layout.colWidth = new.colWidth
                layout.headerHeight = new.headerHeight
                layout.bandHeight = new.bandHeight
                // Mesurer une case coûte cher (une vue SwiftUI complète) : seules les cases changées le sont,
                // sinon chaque ajout remesurait toute la fenêtre de jours (près de 2 s sur un planning chargé).
                layout.rowHeights = Repas.allCases.map { r in new.days.map { height(new, $0, r) }.max() ?? 0 }
                if footerFor != [new.width, new.headerHeight] {
                    layout.footerHeight = fittingHeight(new.footer, width: max(new.width, 300))
                    footerFor = [new.width, new.headerHeight]
                }
            }

            if daysChanged { purgeHeights(around: new.days) }

            if daysChanged {
                // Changement de semaine par le tirer : la nouvelle glisse en place, depuis le côté tiré.
                let shift = shifting
                shifting = nil
                if let forward = shift {
                    let t = CATransition()
                    t.type = .push
                    t.subtype = forward ? .fromRight : .fromLeft
                    t.duration = 0.35
                    t.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    cv.layer.add(t, forKey: "semaine")
                }
                cv.reloadData()
                layout.invalidateLayout()
                cv.layoutIfNeeded()
                guard old?.days.first != nil else {
                    // Premier affichage : la grille s'ouvre sur le jour choisi.
                    cv.pendingDay = new.days.firstIndex(of: new.selected) ?? 0
                    return
                }
                // Arrête le rebond en cours, puis cale la nouvelle semaine : sur son premier jour en avançant,
                // son dernier en reculant, sinon sur le jour choisi.
                cv.setContentOffset(cv.contentOffset, animated: false)
                let x: CGFloat
                if let forward = shift {
                    x = forward ? 0 : maxOffsetX(cv)
                } else {
                    x = min(layout.offset(showing: new.days.firstIndex(of: new.selected) ?? 0), maxOffsetX(cv))
                }
                cv.contentOffset = CGPoint(x: x - cv.adjustedContentInset.left, y: cv.contentOffset.y)
            } else if let old, old.colWidth != new.colWidth {
                zoomTransition(cv, layout, out: new.colWidth < old.colWidth,
                               day: zoomDay ?? new.days.firstIndex(of: new.selected) ?? 0)
            } else if remeasure {
                // Hauteur d'une ligne changée (groupe déplié, plat ajouté) : la grille s'ajuste en douceur.
                // Le nouveau contenu est appliqué hors de l'animation UIKit : sinon SwiftUI prenait l'arrivée d'un plat
                // pour une transition animée, qui restait bloquée (plat invisible jusqu'à la sauvegarde suivante).
                UIView.performWithoutAnimation {
                    reconfigureVisible(cv)
                    cv.layoutIfNeeded()
                }
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    layout.invalidateLayout()
                    cv.layoutIfNeeded()
                }
            } else {
                reconfigureVisible(cv)
            }

            if let old, old.recenter != new.recenter { show(new.selected, in: new, cv) }
        }

        /// Défile jusqu'au jour `day`, sans sortir de sa semaine.
        private func show(_ day: DayKey, in g: WeekGrid, _ cv: UICollectionView) {
            guard let layout else { return }
            let x = layout.offset(showing: g.days.firstIndex(of: day) ?? 0)
            cv.setContentOffset(CGPoint(x: min(x, maxOffsetX(cv)), y: cv.contentOffset.y), animated: true)
        }

        private func height(_ g: WeekGrid, _ day: DayKey, _ repas: Repas) -> CGFloat {
            let ref = SlotRef(date: day, repas: repas)
            let key = g.cellKey(day, repas)
            if let c = Self.heights[g.colWidth]?[ref], c.key == key { return c.height }
            let h = measure(g, day, repas)
            Self.heights[g.colWidth, default: [:]][ref] = (key, h)
            return h
        }

        /// Oublie les hauteurs des cases éloignées de la semaine affichée : le cache, partagé entre les grilles,
        /// grandissait à chaque semaine parcourue. Les semaines voisines restent, pour les allers-retours.
        private func purgeHeights(around days: [DayKey]) {
            guard let first = days.first, let last = days.last else { return }
            let keep = Days.adding(-14, to: first)...Days.adding(14, to: last)
            for w in Self.heights.keys {
                Self.heights[w] = Self.heights[w]?.filter { keep.contains($0.key.date) }
            }
        }

        /// Jours dont au moins la moitié de la colonne est à l'écran.
        private func reportVisible(_ sv: UIScrollView, x: CGFloat) {
            guard let g = parent, let layout, !g.days.isEmpty, sv.bounds.width > 0 else { return }
            let centered = g.days.indices.filter {
                let mid = layout.x(ofDay: $0) + layout.colWidth / 2
                return mid >= x && mid <= x + sv.bounds.width
            }
            guard let first = centered.first, let last = centered.last else { return }
            let range = g.days[first]...g.days[last]
            guard range != lastVisible else { return }
            lastVisible = range
            // Hors de la mise à jour en cours de la vue SwiftUI.
            DispatchQueue.main.async { g.visible(range) }
        }

        /// Hauteur idéale d'une case, à la largeur de sa colonne (texte sur plusieurs lignes compris).
        private func measure(_ g: WeekGrid, _ day: DayKey, _ repas: Repas) -> CGFloat {
            fittingHeight(g.cell(day, repas, true), width: g.colWidth)
        }

        /// Mesure UIKit des cellules qui s'adaptent à leur contenu : largeur imposée, hauteur au plus juste.
        private func fittingHeight(_ content: AnyView, width: CGFloat) -> CGFloat {
            let v = UIHostingConfiguration { content }.margins(.all, 0).makeContentView()
            let size = v.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
            return ceil(size.height)
        }

        private func maxOffsetX(_ cv: UICollectionView) -> CGFloat {
            max(0, cv.contentSize.width - cv.bounds.width + cv.adjustedContentInset.right)
        }

        /// Contenu SwiftUI à jour dans les cellules visibles (case survolée, plat déplacé…).
        private func reconfigureVisible(_ cv: UICollectionView) {
            for ip in cv.indexPathsForVisibleItems {
                if let c = cv.cellForItem(at: ip) { configure(c, item: ip.item) }
            }
            for kind in [Kind.header, Kind.band, Kind.footer] {
                for ip in cv.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
                    if let v = cv.supplementaryView(forElementKind: kind, at: ip) as? UICollectionViewCell {
                        configure(v, kind: kind, item: ip.item)
                    }
                }
            }
        }

        private func configure(_ c: UICollectionViewCell, item: Int) {
            guard let g = parent, item / WeekGrid.rows < g.days.count else { return }
            c.clipsToBounds = true
            let repas = Repas(slot: item % WeekGrid.rows)
            c.contentConfiguration = UIHostingConfiguration { g.cell(g.days[item / WeekGrid.rows], repas, false) }.margins(.all, 0)
        }

        private func configure(_ v: UICollectionViewCell, kind: String, item: Int) {
            guard let g = parent else { return }
            let content: AnyView
            switch kind {
            case Kind.header where item < g.days.count: content = g.header(g.days[item])
            case Kind.band where item / WeekGrid.rows < g.days.count:
                content = g.band(g.days[item / WeekGrid.rows], Repas(slot: item % WeekGrid.rows))
            case Kind.footer: content = g.footer
            default: content = AnyView(EmptyView())
            }
            v.contentConfiguration = UIHostingConfiguration { content }.margins(.all, 0)
        }

        // Données : une case par jour × repas (item = jour × `rows` + repas).
        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            (parent?.days.count ?? 0) * WeekGrid.rows
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
            let c = cv.dequeueReusableCell(withReuseIdentifier: Kind.cell, for: ip)
            configure(c, item: ip.item)
            return c
        }

        func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                            at ip: IndexPath) -> UICollectionReusableView {
            let v = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: ip)
            if let c = v as? UICollectionViewCell { configure(c, kind: kind, item: ip.item) }
            return v
        }

        // MARK: Dépôt d'un plat

        private func slot(at session: UIDropSession) -> SlotRef? {
            guard let cv = collectionView, let layout, let g = parent,
                  let (day, slot) = layout.slot(at: session.location(in: cv)), day < g.days.count else { return nil }
            return SlotRef(date: g.days[day], repas: Repas(slot: slot))
        }

        private func setHover(_ ref: SlotRef?) {
            guard ref != hovered else { return }
            hovered = ref
            parent?.hover(ref)
        }

        func dropInteraction(_ i: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil && parent?.canDrop() == true
        }

        func dropInteraction(_ i: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            let ref = slot(at: session)
            setHover(ref)
            return UIDropProposal(operation: ref == nil ? .cancel : .copy)
        }

        func dropInteraction(_ i: UIDropInteraction, sessionDidExit session: UIDropSession) { setHover(nil) }
        func dropInteraction(_ i: UIDropInteraction, sessionDidEnd session: UIDropSession) { setHover(nil) }

        func dropInteraction(_ i: UIDropInteraction, performDrop session: UIDropSession) {
            let ref = slot(at: session)
            setHover(nil)
            if let ref { parent?.drop(ref.date, ref.repas) }
        }

        // MARK: Pincer pour changer de niveau

        /// Bascule de niveau en zoom : une image de l'ancienne grille s'efface en se contractant (dézoom) ou en
        /// grossissant (zoom) autour des doigts, puis la nouvelle, déjà en place, apparaît depuis le même point.
        /// Les colonnes ne glissent pas d'une largeur à l'autre (ça ressemblait à un défilement de côté).
        private func zoomTransition(_ cv: UICollectionView, _ layout: WeekGridLayout, out: Bool, day: Int) {
            let point = zoomPoint ?? CGPoint(x: cv.frame.midX, y: cv.frame.midY)
            zoomPoint = nil
            zoomDay = nil
            let snapshot = cv.snapshotView(afterScreenUpdates: false)
            UIView.performWithoutAnimation {
                reconfigureVisible(cv)
                layout.invalidateLayout()
                cv.layoutIfNeeded()
                let x = min(layout.offset(showing: day), maxOffsetX(cv))
                cv.contentOffset = CGPoint(x: x - cv.adjustedContentInset.left, y: cv.contentOffset.y)
                cv.layoutIfNeeded()
            }
            guard let snapshot, let container = cv.superview else { return }
            snapshot.frame = cv.frame
            container.insertSubview(snapshot, aboveSubview: cv)
            /// Mise à l'échelle autour du point des doigts.
            func scaled(_ v: UIView, _ k: CGFloat) -> CGAffineTransform {
                let dx = point.x - v.center.x, dy = point.y - v.center.y
                return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: k, y: k).translatedBy(x: -dx, y: -dy)
            }
            cv.alpha = 0
            cv.transform = scaled(cv, out ? 1.12 : 0.88)
            // L'échelle change sur toute la durée ; l'ancienne s'efface dans la première moitié et la nouvelle apparaît
            // ensuite, pour éviter une double image floue au milieu.
            UIView.animateKeyframes(withDuration: 0.34, delay: 0, options: [.calculationModeCubic, .allowUserInteraction]) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                    snapshot.transform = scaled(snapshot, out ? 0.85 : 1.15)
                    cv.transform = .identity
                }
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) { snapshot.alpha = 0 }
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) { cv.alpha = 1 }
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }

        /// Une bascule par geste, dès que le pincement est franc : resserrer vers la vue d'ensemble, écarter vers
        /// le détail. Pas de zoom continu : le texte resterait flou et les hauteurs mesurées fausses pendant le geste.
        @objc func pinched(_ p: UIPinchGestureRecognizer) {
            guard let cv = collectionView, let layout, let g = parent else { return }
            switch p.state {
            case .began:
                zoomed = false
            case .changed where !zoomed && (p.scale < 0.85 || p.scale > 1.18):
                zoomed = true
                zoomPoint = p.location(in: cv.superview)
                zoomDay = layout.slot(at: p.location(in: cv))?.day
                    ?? min(Int(max(0, p.location(in: cv).x) / layout.colStep), max(g.days.count - 1, 0))
                g.zoom(p.scale < 1)
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Changer de semaine en tirant

        func scrollViewDidScroll(_ sv: UIScrollView) {
            // Pas de rebond en haut (UIKit ne le règle que pour les deux bords à la fois).
            let top = -sv.adjustedContentInset.top
            if sv.contentOffset.y < top { sv.contentOffset.y = top }
            let x = sv.contentOffset.x + sv.adjustedContentInset.left
            reportVisible(sv, x: x)
            guard !turning, let cv = sv as? UICollectionView, let g = parent else { return }
            let beyond = x - maxOffsetX(cv), before = -x
            let over = max(beyond, before)
            // Seul le doigt posé fait apparaître la pastille : un défilement lancé qui rebondit au bord ne tire pas.
            // Une fois là, elle suit le rebond qui la vide, jusqu'au retour au bord.
            let appear: CGFloat = 8
            guard over > appear, sv.isTracking || pulled != nil else { return setPull(nil) }
            // Compté depuis l'apparition de la pastille : elle arrive toute blanche.
            g.meter.progress = min(1, (over - appear) / (WeekGrid.pullThreshold - appear))
            setPull(WeekPull(forward: beyond > before, armed: sv.isTracking && over > WeekGrid.pullThreshold))
        }

        /// Lâcher au-delà du seuil, doigt presque arrêté : la semaine voisine est demandée, et arrive par une
        /// transition de page. Un swipe lâché en pleine course (plus de 1 000 pt/s) n'est pas un tirer : le rebond
        /// d'iOS ramène la grille au bord, comme sous le seuil.
        func scrollViewWillEndDragging(_ sv: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset target: UnsafeMutablePointer<CGPoint>) {
            guard let p = pulled, p.armed, abs(velocity.x) < 1, let g = parent else {
                if let p = pulled { setPull(WeekPull(forward: p.forward, armed: false)) }
                return
            }
            shifting = p.forward
            turning = true
            g.meter.progress = 1
            target.pointee = sv.contentOffset
            g.shift(p.forward)
            // Pastille pleine le temps que la page tourne, puis elle s'efface.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.turning = false
                self?.setPull(nil)
            }
        }

        private func setPull(_ p: WeekPull?) {
            guard p != pulled else { return }
            pulled = p
            parent?.pull(p)
        }
    }
}

/// Ouvre la grille sur le jour choisi (index dans la grille) dès qu'elle a sa taille.
final class GridCollectionView: UICollectionView {
    var pendingDay: Int?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let day = pendingDay, bounds.width > 0, contentSize.width > 0,
              let layout = collectionViewLayout as? WeekGridLayout else { return }
        pendingDay = nil
        let maxX = max(0, contentSize.width - bounds.width + adjustedContentInset.right)
        contentOffset.x = min(layout.offset(showing: day), maxX) - adjustedContentInset.left
    }
}

// MARK: - Mise en page

/// Colonnes = jours, lignes = repas (bande de 24 pt, puis la case, puis un filet). Toutes les cases d'un repas
/// ont la hauteur de la plus haute. L'en-tête des jours est recalé en haut de la zone visible à chaque défilement,
/// et le texte d'aide sous la grille, sur son bord gauche.
final class WeekGridLayout: UICollectionViewLayout {
    var dayCount = 0
    var colWidth: CGFloat = 162
    var headerHeight: CGFloat = 38
    var bandHeight: CGFloat = 24
    var rowHeights = [CGFloat](repeating: 0, count: WeekGrid.rows)
    var footerHeight: CGFloat = 0
    /// Largeur d'une colonne avec son filet.
    var colStep: CGFloat { colWidth + 1 }
    /// Bord gauche de la colonne du jour `day` (index dans la grille).
    func x(ofDay day: Int) -> CGFloat { CGFloat(day) * colStep }

    /// Décalage qui montre le jour `day` à gauche.
    func offset(showing day: Int) -> CGFloat { x(ofDay: day) }

    private var cells: [UICollectionViewLayoutAttributes] = []
    private var bands: [UICollectionViewLayoutAttributes] = []
    private var separators: [UICollectionViewLayoutAttributes] = []
    private var gridBottom: CGFloat = 0

    override init() {
        super.init()
        register(SeparatorView.self, forDecorationViewOfKind: WeekGrid.Kind.separator)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var width: CGFloat { dayCount > 0 ? x(ofDay: dayCount - 1) + colWidth : 0 }

    /// Faux après une simple invalidation de défilement : cases, bandes et filets ne bougent pas, inutile de les
    /// recalculer à chaque image (seuls l'en-tête figé et le texte d'aide se recalent, voir `invalidationContext`).
    private var needsRebuild = true

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        if !(context is DefilementContext) { needsRebuild = true }
        super.invalidateLayout(with: context)
    }

    override func prepare() {
        guard needsRebuild else { return }
        needsRebuild = false
        cells = []; bands = []; separators = []
        var y = headerHeight
        for slot in 0..<WeekGrid.rows {
            for day in 0..<dayCount {
                let ip = IndexPath(item: day * WeekGrid.rows + slot, section: 0)
                let x = x(ofDay: day)
                let b = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: WeekGrid.Kind.band, with: ip)
                b.frame = CGRect(x: x, y: y, width: colWidth, height: bandHeight)
                bands.append(b)
                let c = UICollectionViewLayoutAttributes(forCellWith: ip)
                c.frame = CGRect(x: x, y: y + bandHeight, width: colWidth, height: rowHeights[slot])
                cells.append(c)
            }
            y += bandHeight + rowHeights[slot]
            // Filet sous la ligne de repas, sur toute la largeur.
            let s = UICollectionViewLayoutAttributes(forDecorationViewOfKind: WeekGrid.Kind.separator,
                                                     with: IndexPath(item: 1000 + slot, section: 0))
            s.frame = CGRect(x: 0, y: y, width: width, height: 1)
            separators.append(s)
            y += 1
        }
        gridBottom = y
        // Filets verticaux entre les jours, en-tête compris (au-dessus de lui, qui est figé).
        for day in 1..<max(dayCount, 1) {
            let s = UICollectionViewLayoutAttributes(forDecorationViewOfKind: WeekGrid.Kind.separator,
                                                     with: IndexPath(item: 100 + day, section: 0))
            s.frame = CGRect(x: x(ofDay: day) - 1, y: 0, width: 1, height: gridBottom)
            s.zIndex = 11
            separators.append(s)
        }
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: width, height: gridBottom + footerHeight)
    }

    /// En-tête du jour `day`, figé en haut de la zone visible.
    private func headerAttributes(_ day: Int) -> UICollectionViewLayoutAttributes {
        let a = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: WeekGrid.Kind.header,
                                                 with: IndexPath(item: day, section: 0))
        let top = (collectionView.map { $0.contentOffset.y + $0.adjustedContentInset.top }) ?? 0
        a.frame = CGRect(x: x(ofDay: day), y: max(0, top), width: colWidth, height: headerHeight)
        a.zIndex = 10
        return a
    }

    /// Texte d'aide sous la grille, calé sur le bord gauche visible.
    private func footerAttributes() -> UICollectionViewLayoutAttributes {
        fullWidth(WeekGrid.Kind.footer, y: gridBottom, height: footerHeight)
    }


    /// Élément de la largeur visible, qui suit le défilement horizontal pour rester en place à l'écran.
    private func fullWidth(_ kind: String, y: CGFloat, height: CGFloat) -> UICollectionViewLayoutAttributes {
        let a = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: IndexPath(item: 0, section: 0))
        let cv = collectionView
        let left = (cv.map { $0.contentOffset.x + $0.adjustedContentInset.left }) ?? 0
        let w = cv?.bounds.width ?? width
        a.frame = CGRect(x: max(0, min(left, width - w)), y: y, width: w, height: height)
        return a
    }

    /// Jour (index de colonne) et repas sous un point de la grille : la case ou sa bande de titre.
    func slot(at p: CGPoint) -> (day: Int, slot: Int)? {
        guard let c = cells.first(where: { $0.frame.union($0.frame.offsetBy(dx: 0, dy: -bandHeight)).contains(p) })
        else { return nil }
        return (c.indexPath.item / WeekGrid.rows, c.indexPath.item % WeekGrid.rows)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var all = (cells + bands + separators).filter { $0.frame.intersects(rect) }
        all += (0..<dayCount).map(headerAttributes).filter { $0.frame.intersects(rect) }
        if footerHeight > 0 { all.append(footerAttributes()) }
        return all
    }

    override func layoutAttributesForItem(at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        cells.first { $0.indexPath == ip }
    }

    override func layoutAttributesForSupplementaryView(ofKind kind: String, at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        switch kind {
        case WeekGrid.Kind.header: ip.item < dayCount ? headerAttributes(ip.item) : nil
        case WeekGrid.Kind.footer: footerAttributes()
        default: bands.first { $0.indexPath == ip }
        }
    }

    override func layoutAttributesForDecorationView(ofKind kind: String, at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        separators.first { $0.indexPath == ip }
    }

    /// À chaque défilement, l'en-tête et le texte d'aide se recalent.
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

    /// Défilement : seuls l'en-tête des jours et le texte d'aide sont invalidés.
    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let c = DefilementContext()
        c.invalidateSupplementaryElements(ofKind: WeekGrid.Kind.header,
                                          at: (0..<dayCount).map { IndexPath(item: $0, section: 0) })
        if footerHeight > 0 {
            c.invalidateSupplementaryElements(ofKind: WeekGrid.Kind.footer, at: [IndexPath(item: 0, section: 0)])
        }
        return c
    }

    /// Invalidation due au seul défilement (voir `needsRebuild`).
    private final class DefilementContext: UICollectionViewLayoutInvalidationContext {}
}

/// Filet de 1 pt entre les jours et sous chaque repas.
final class SeparatorView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "filet")
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Avancée du tirer vers le seuil (0 à 1).
@Observable final class PullMeter {
    var progress: CGFloat = 0
}

/// Tirer en cours vers la semaine voisine : dans quel sens, et si le lâcher y mènera.
struct WeekPull: Equatable {
    var forward: Bool
    var armed: Bool
}
