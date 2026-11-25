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

    /// Temps réellement passé par catégorie sur le jour donné (entrées réelles seulement, tronquées au jour).
    public static func totals(_ all: [Entry], on day: Date, now: Date,
                              calendar: Calendar = .current) -> [(category: String, duration: TimeInterval)] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var sums: [String: TimeInterval] = [:]
        for e in entries(all, kind: .actual, on: day, now: now, calendar: calendar) {
            let s = max(e.start, dayStart)
            let f = min(e.effectiveEnd(now: now), dayEnd)
            if f > s { sums[e.category, default: 0] += f.timeIntervalSince(s) }
        }
        return sums.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
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
