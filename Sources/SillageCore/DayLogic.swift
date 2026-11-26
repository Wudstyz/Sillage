import Foundation

/// Une entrée placée dans une colonne (les tâches simultanées se mettent côte à côte).
public struct PlacedEntry: Equatable, Sendable {
    public let entry: Entry
    public let lane: Int
    public let lanes: Int
}

public enum DayLogic {
    /// Entrées qui touchent le jour donné, triées par début.
    public static func entries(_ all: [Entry], kind: EntryKind? = nil, on day: Date, now: Date,
                               calendar: Calendar = .current) -> [Entry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return all
            .filter { kind == nil || $0.kind == kind }
            .filter { $0.start < end && $0.effectiveEnd(now: now) > start }
            .sorted { $0.start < $1.start }
    }

    /// Répartit les entrées qui se chevauchent sur des colonnes côte à côte.
    public static func lanes(_ list: [Entry], now: Date) -> [PlacedEntry] {
        var result: [PlacedEntry] = []
        var group: [(entry: Entry, lane: Int)] = []
        var laneEnds: [Date] = []
        var groupEnd = Date.distantPast

        func flush() {
            let count = max(1, (group.map(\.lane).max() ?? 0) + 1)
            result += group.map { PlacedEntry(entry: $0.entry, lane: $0.lane, lanes: count) }
            group = []
            laneEnds = []
        }

        for e in list.sorted(by: { $0.start < $1.start }) {
            if e.start >= groupEnd { flush() }
            let end = e.effectiveEnd(now: now)
            let lane = laneEnds.firstIndex { $0 <= e.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            group.append((e, lane))
            groupEnd = max(groupEnd, end)
        }
        flush()
        return result
    }

    /// Clé de regroupement d'une tâche : le titre sans espaces superflus, sans majuscules ni accents.
    public static func taskKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private struct Span {
        let entry: Entry
        let start: Date
        let end: Date
    }

    /// Durée comptée pour chaque tranche de temps réel du jour (tronquée au jour).
    /// `shared` : quand plusieurs tâches tournent en même temps, chacune ne compte que sa part du temps
    /// (deux tâches simultanées pendant une heure : une demi-heure chacune). Le total est alors le temps
    /// réellement écoulé ; sans cela, deux tâches parallèles d'une heure compteraient deux heures.
    private static func countedSpans(_ all: [Entry], on day: Date, now: Date, shared: Bool,
                                     calendar: Calendar) -> [(entry: Entry, duration: TimeInterval)] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var spans: [Span] = []
        for e in entries(all, kind: .actual, on: day, now: now, calendar: calendar) {
            let s = max(e.start, dayStart)
            let f = min(e.effectiveEnd(now: now), dayEnd)
            if f > s { spans.append(Span(entry: e, start: s, end: f)) }
        }
        var counted = [TimeInterval](repeating: 0, count: spans.count)
        if shared {
            // Balayage : entre deux bornes consécutives, le temps est partagé à parts égales entre les tâches actives.
            let bounds = Array(Set(spans.flatMap { [$0.start, $0.end] })).sorted()
            for (a, b) in zip(bounds, bounds.dropFirst()) {
                let active = spans.indices.filter { spans[$0].start <= a && spans[$0].end >= b }
                guard !active.isEmpty else { continue }
                let part = b.timeIntervalSince(a) / Double(active.count)
                for i in active { counted[i] += part }
            }
        } else {
            for i in spans.indices { counted[i] = spans[i].end.timeIntervalSince(spans[i].start) }
        }
        return zip(spans, counted).map { ($0.entry, $1) }
    }

    /// Temps réellement passé par catégorie sur le jour donné (entrées réelles seulement, tronquées au jour).
    public static func totals(_ all: [Entry], on day: Date, now: Date, shared: Bool = true,
                              calendar: Calendar = .current) -> [(category: String, duration: TimeInterval)] {
        var sums: [String: TimeInterval] = [:]
        for (e, d) in countedSpans(all, on: day, now: now, shared: shared, calendar: calendar) { sums[e.category, default: 0] += d }
        return sums.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// Temps passé par tâche (titres identiques regroupés) : « SFCO », « Sillage »… plutôt que « Travail ».
    /// Le titre affiché est la graphie la plus utilisée (par durée) ; la catégorie est celle où la tâche a passé le plus de temps.
    public static func taskTotals(_ all: [Entry], on day: Date, now: Date, shared: Bool = true,
                                  calendar: Calendar = .current) -> [(title: String, category: String, duration: TimeInterval)] {
        struct Acc { var spellings: [String: TimeInterval] = [:]; var byCategory: [String: TimeInterval] = [:] }
        var groups: [String: Acc] = [:]
        for (e, d) in countedSpans(all, on: day, now: now, shared: shared, calendar: calendar) {
            var acc = groups[taskKey(e.title)] ?? Acc()
            acc.spellings[e.title.trimmingCharacters(in: .whitespaces), default: 0] += d
            acc.byCategory[e.category, default: 0] += d
            groups[taskKey(e.title)] = acc
        }
        return groups.values.map { g in
            let title = g.spellings.max { $0.value < $1.value }!.key
            let main = g.byCategory.max { $0.value < $1.value }!.key
            return (title, main, g.byCategory.values.reduce(0, +))
        }
        .sorted { $0.duration > $1.duration }
    }

    /// Temps passé par tâche **et** par catégorie sur un jour : une tâche faite dans deux catégories donne deux lignes.
    /// Sert à détailler une catégorie par tâche (le temps simultané est réparti comme ailleurs).
    public static func taskCategoryTotals(_ all: [Entry], on day: Date, now: Date, shared: Bool = true,
                                          calendar: Calendar = .current) -> [(title: String, category: String, duration: TimeInterval)] {
        struct Key: Hashable { let task: String; let category: String }
        struct Acc { var spellings: [String: TimeInterval] = [:]; var total: TimeInterval = 0 }
        var groups: [Key: Acc] = [:]
        for (e, d) in countedSpans(all, on: day, now: now, shared: shared, calendar: calendar) {
            let key = Key(task: taskKey(e.title), category: e.category)
            var acc = groups[key] ?? Acc()
            acc.spellings[e.title.trimmingCharacters(in: .whitespaces), default: 0] += d
            acc.total += d
            groups[key] = acc
        }
        return groups.map { ($0.value.spellings.max { $0.value < $1.value }!.key, $0.key.category, $0.value.total) }
            .sorted { $0.duration > $1.duration }
    }

    /// Des tâches réelles se chevauchent-elles ce jour-là ? (le bilan répartit alors le temps entre elles)
    public static func hasSimultaneous(_ all: [Entry], on day: Date, now: Date, calendar: Calendar = .current) -> Bool {
        lanes(entries(all, kind: .actual, on: day, now: now, calendar: calendar), now: now).contains { $0.lanes > 1 }
    }

    /// Au-delà de cette durée, une tâche encore « en cours » est probablement oubliée.
    public static let forgottenThreshold: TimeInterval = 12 * 3600

    public static func isLikelyForgotten(_ e: Entry, now: Date) -> Bool {
        e.isRunning && now.timeIntervalSince(e.start) >= forgottenThreshold
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? String(format: "%d h %02d", h, m) : "\(m) min"
    }
}
