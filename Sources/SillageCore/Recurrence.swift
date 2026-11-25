import Foundation

/// Règle de répétition d'un rendez-vous.
public struct Recurrence: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable { case daily, weekly, monthly, yearly }

    public var frequency: Frequency
    /// « Toutes les N … » (1 = chaque).
    public var interval: Int
    /// Hebdomadaire : jours choisis (1 = dimanche … 7 = samedi, comme `Calendar`). Vide : le jour du début.
    public var weekdays: [Int]
    /// Dernier jour inclus ; `nil` = sans fin.
    public var until: Date?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], until: Date? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.until = until
    }

    /// Le jour `day` est-il une occurrence, la première étant `firstDay` ?
    public func matches(day: Date, firstDay: Date, calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day), f = calendar.startOfDay(for: firstDay)
        guard d >= f else { return false }
        if let u = until, d > calendar.startOfDay(for: u) { return false }
        let n = max(1, interval)
        let cf = calendar.dateComponents([.year, .month, .day], from: f)
        let cd = calendar.dateComponents([.year, .month, .day], from: d)
        let dom = min(cf.day!, calendar.range(of: .day, in: .month, for: d)!.count) // 31 → dernier jour du mois court

        switch frequency {
        case .daily:
            return (calendar.dateComponents([.day], from: f, to: d).day ?? 0) % n == 0
        case .weekly:
            let days = weekdays.isEmpty ? [calendar.component(.weekday, from: f)] : weekdays
            guard days.contains(calendar.component(.weekday, from: d)) else { return false }
            let wf = calendar.dateInterval(of: .weekOfYear, for: f)!.start
            let wd = calendar.dateInterval(of: .weekOfYear, for: d)!.start
            return ((calendar.dateComponents([.day], from: wf, to: wd).day ?? 0) / 7) % n == 0
        case .monthly:
            let months = (cd.year! - cf.year!) * 12 + cd.month! - cf.month!
            return months % n == 0 && cd.day! == dom
        case .yearly:
            return cd.month! == cf.month! && (cd.year! - cf.year!) % n == 0 && cd.day! == dom
        }
    }
}

/// Une série de rendez-vous : un modèle, une règle, et le dernier jour déjà généré.
/// Chaque occurrence est une vraie entrée (modifiable, déplaçable, « J'y suis »…) créée à l'avance.
public struct Series: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var template: Entry
    public var rule: Recurrence
    public var generatedThrough: Date

    public init(id: UUID = UUID(), template: Entry, rule: Recurrence, generatedThrough: Date) {
        self.id = id
        self.template = template
        self.rule = rule
        self.generatedThrough = generatedThrough
    }

    /// Crée la série à partir d'un rendez-vous : lui-même est la première occurrence.
    public static func make(from entry: Entry, rule: Recurrence, calendar: Calendar = .current) -> (series: Series, first: Entry) {
        var first = entry
        let id = UUID()
        first.seriesID = id
        return (Series(id: id, template: first, rule: rule, generatedThrough: calendar.startOfDay(for: entry.start)), first)
    }

    /// Occurrences entre deux jours (inclus). L'heure du modèle est conservée (heure d'été comprise).
    public func occurrences(from: Date, through: Date, calendar: Calendar = .current) -> [Entry] {
        let first = calendar.startOfDay(for: template.start)
        var day = max(calendar.startOfDay(for: from), first)
        let last = calendar.startOfDay(for: through)
        let tod = calendar.dateComponents([.hour, .minute], from: template.start)
        let duration = (template.end ?? template.start.addingTimeInterval(3600)).timeIntervalSince(template.start)
        var out: [Entry] = []
        var guardCount = 0
        while day <= last && guardCount < 1500 {
            if rule.matches(day: day, firstDay: first, calendar: calendar),
               let s = calendar.date(bySettingHour: tod.hour!, minute: tod.minute!, second: 0, of: day) {
                out.append(Entry(title: template.title, category: template.category, kind: .planned, start: s,
                                 end: s.addingTimeInterval(duration), seriesID: id,
                                 reminderMinutes: template.reminderMinutes))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            guardCount += 1
        }
        return out
    }

    /// Génère les occurrences manquantes jusqu'à `horizonDays` jours dans le futur.
    /// Ne recrée jamais une occurrence supprimée : on ne génère qu'après `generatedThrough`.
    @discardableResult
    public static func topUp(_ series: inout [Series], entries: inout [Entry], now: Date, horizonDays: Int = 365,
                             calendar: Calendar = .current) -> Bool {
        let target = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: now))!
        var changed = false
        for i in series.indices where series[i].generatedThrough < target {
            let from = calendar.date(byAdding: .day, value: 1, to: series[i].generatedThrough)!
            entries += series[i].occurrences(from: from, through: target, calendar: calendar)
            series[i].generatedThrough = target
            changed = true
        }
        return changed
    }

    /// Met fin à la série à partir de `from` : supprime les occurrences suivantes pas encore honorées
    /// et empêche d'en générer d'autres. Les occurrences déjà vécues restent.
    public static func end(_ id: UUID, from: Date, series: inout [Series], entries: inout [Entry],
                           calendar: Calendar = .current) {
        let snapshot = entries
        entries.removeAll { $0.seriesID == id && $0.kind == .planned && $0.start >= from && !Actions.isArrived($0, in: snapshot) }
        guard let i = series.firstIndex(where: { $0.id == id }) else { return }
        let until = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: from))!
        if until < calendar.startOfDay(for: series[i].template.start) {
            series.remove(at: i)
        } else {
            series[i].rule.until = until
        }
    }
}

/// Rappels : notifications avant un rendez-vous prévu.
public enum Reminders {
    public static let options: [(label: String, minutes: Int?)] = [
        ("Aucun", nil), ("À l'heure", 0), ("5 min avant", 5), ("10 min avant", 10), ("15 min avant", 15),
        ("30 min avant", 30), ("1 h avant", 60), ("1 jour avant", 1440),
    ]

    public static func fireDate(_ e: Entry) -> Date? {
        guard e.kind == .planned, let m = e.reminderMinutes else { return nil }
        return e.start.addingTimeInterval(-Double(m) * 60)
    }

    /// Les prochains rappels à programmer (macOS limite à 64 notifications en attente par app).
    public static func upcoming(_ entries: [Entry], now: Date, limit: Int = 60) -> [(entry: Entry, fire: Date)] {
        entries.compactMap { e -> (Entry, Date)? in
            guard let f = fireDate(e), f > now, !Actions.isArrived(e, in: entries) else { return nil }
            return (e, f)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(limit)
        .map { (entry: $0.0, fire: $0.1) }
    }

    public static func body(for e: Entry) -> String {
        let time = e.start.formatted(date: .omitted, time: .shortened)
        guard let m = e.reminderMinutes, m > 0 else { return "C'est l'heure · \(time)" }
        return "Dans \(DayLogic.formatDuration(Double(m) * 60)) · \(time)"
    }
}
