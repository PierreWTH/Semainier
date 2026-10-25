import Foundation

/// Un jour du planning, identifié par sa date sous forme AAAAMMJJ (ex. 20261015).
/// Indépendant des fuseaux horaires et des changements d'heure.
typealias DayKey = Int

nonisolated enum Days {
    /// Créé une seule fois : ces fonctions sont appelées des milliers de fois par rendu.
    /// Le fuseau suit celui de l'appareil s'il change.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        return c
    }()
    private static let fr = Locale(identifier: "fr_FR")

    static func key(_ date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year! * 10000 + c.month! * 100 + c.day!
    }

    static var today: DayKey { key(.now) }

    /// Midi du jour (évite les surprises de changement d'heure).
    static func date(_ key: DayKey) -> Date {
        calendar.date(from: DateComponents(year: key / 10000, month: key / 100 % 100, day: key % 100, hour: 12))!
    }

    static func adding(_ n: Int, to key: DayKey) -> DayKey {
        Days.key(calendar.date(byAdding: .day, value: n, to: date(key))!)
    }

    /// Nombre de jours de `a` à `b` (négatif si `b` est avant).
    static func distance(from a: DayKey, to b: DayKey) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day!
    }

    static func range(from start: DayKey, count: Int) -> [DayKey] {
        (0..<count).map { adding($0, to: start) }
    }

    /// Prochaine occurrence (aujourd'hui compris) d'un jour de la semaine (0 = lundi).
    static func next(weekday: Int, from start: DayKey = today) -> DayKey {
        let w = weekdayIndex(start)
        return adding((weekday - w + 7) % 7, to: start)
    }

    /// Premier jour de la semaine affichée qui contient `key` : le lundi précédent (ou le jour même),
    /// ou `key` lui-même quand la semaine part du jour courant.
    static func weekStart(_ key: DayKey, fromMonday: Bool) -> DayKey {
        fromMonday ? adding(-weekdayIndex(key), to: key) : key
    }

    /// Début de la semaine qui contient `key`, les semaines partant de `home` par pas de 7 jours
    /// (vers l'avant comme vers l'arrière).
    static func weekStart(containing key: DayKey, home: DayKey) -> DayKey {
        let n = distance(from: home, to: key)
        return adding(Int((Double(n) / 7).rounded(.down)) * 7, to: home)
    }

    /// Jours désignés par leur décalage depuis `today` (0 = aujourd'hui) : jours de courses et « À préparer ».
    static func chosen(_ offsets: [Int], from today: DayKey = today) -> Set<DayKey> {
        Set(offsets.map { adding($0, to: today) })
    }

    static func weekdayIndex(_ key: DayKey) -> Int { Week.weekdayIndex(date(key), calendar: calendar) }

    /// « Jeudi »
    static func weekday(_ key: DayKey) -> String { Week.days[weekdayIndex(key)] }
    /// « Jeu »
    static func shortWeekday(_ key: DayKey) -> String { Week.short[weekdayIndex(key)] }
    /// « 15 »
    static func dayNumber(_ key: DayKey) -> String { String(key % 100) }
    /// « Jeu 15 »
    static func shortLabel(_ key: DayKey) -> String { shortWeekday(key) + " " + dayNumber(key) }

    /// « 15 octobre », « 1er novembre »
    static func dayMonth(_ key: DayKey) -> String {
        let d = key % 100
        return (d == 1 ? "1er" : String(d)) + " " + date(key).formatted(.dateTime.month(.wide).locale(fr))
    }

    /// « Jeudi 15 octobre »
    static func longLabel(_ key: DayKey) -> String { weekday(key) + " " + dayMonth(key) }

    /// « aujourd'hui », « demain », « hier », ou nil.
    static func relative(_ key: DayKey, today: DayKey = today) -> String? {
        switch distance(from: today, to: key) {
        case 0: "aujourd'hui"
        case 1: "demain"
        case -1: "hier"
        default: nil
        }
    }

    /// « du 15 au 21 octobre », ou « du 28 septembre au 4 octobre » à cheval sur deux mois.
    static func rangeText(_ start: DayKey, _ end: DayKey) -> String {
        let sameMonth = start / 100 == end / 100
        let first = start % 100 == 1 ? "1er" : String(start % 100)
        return sameMonth ? "du \(first) au \(dayMonth(end))" : "du \(dayMonth(start)) au \(dayMonth(end))"
    }

    /// « 16 – 22 oct. », ou « 28 sept. – 4 oct. » à cheval sur deux mois.
    static func shortRangeText(_ start: DayKey, _ end: DayKey) -> String {
        let month = { (k: DayKey) in date(k).formatted(.dateTime.month(.abbreviated).locale(fr)) }
        let first = start / 100 == end / 100 ? String(start % 100) : "\(start % 100) \(month(start))"
        return "\(first) – \(end % 100) \(month(end))"
    }

    /// Format des sauvegardes : « 2026-10-15 ».
    static func iso(_ key: DayKey) -> String {
        String(format: "%04d-%02d-%02d", key / 10000, key / 100 % 100, key % 100)
    }

    static func parseISO(_ s: String) -> DayKey? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return p[0] * 10000 + p[1] * 100 + p[2]
    }
}
