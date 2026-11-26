import Foundation

/// Période d'un rapport : un jour, une semaine, un mois, ou tout l'historique.
public enum ReportPeriod: String, CaseIterable, Sendable {
    case day, week, month, all
}

/// Temps passé sur une tâche un jour donné.
public struct TaskDay: Equatable, Sendable {
    public let day: Date
    public let duration: TimeInterval
}

/// Tout ce qu'on sait d'une tâche sur une période.
public struct TaskSummary: Equatable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let category: String
    /// Temps compté (réparti entre les tâches simultanées).
    public let total: TimeInterval
    /// Nombre de séances (entrées réelles) commencées dans la période.
    public let sessions: Int
    public let activeDays: Int
    public let first: Date?
    public let last: Date?
    public let perDay: [TaskDay]

    /// Moyenne par jour où la tâche a été faite.
    public var averagePerActiveDay: TimeInterval { activeDays > 0 ? total / Double(activeDays) : 0 }
}

/// Tout ce qu'on sait d'une catégorie sur une période : temps, séances, tâches qu'elle contient, jour par jour.
public struct CategorySummary: Equatable, Identifiable, Sendable {
    public var id: String { category }
    public let category: String
    /// Temps compté (réparti entre les tâches simultanées).
    public let total: TimeInterval
    public let sessions: Int
    public let activeDays: Int
    public let first: Date?
    public let last: Date?
    public let perDay: [TaskDay]
    /// Les tâches faites dans cette catégorie, de la plus longue à la plus courte.
    public let tasks: [TaskTotal]

    public var averagePerActiveDay: TimeInterval { activeDays > 0 ? total / Double(activeDays) : 0 }
}

public enum Reports {
    /// Les jours (débuts de journée) couverts par une période autour de `anchor`.
    /// `.all` va de la toute première entrée réelle à aujourd'hui.
    public static func days(for period: ReportPeriod, anchor: Date, entries: [Entry], now: Date,
                            calendar: Calendar = .current) -> [Date] {
        switch period {
        case .day:
            return [calendar.startOfDay(for: anchor)]
        case .week:
            return CalendarGrid.week(containing: anchor, calendar: calendar)
        case .month:
            return CalendarGrid.month(containing: anchor, calendar: calendar).flatMap { $0 }
                .filter { CalendarGrid.isSameMonth($0, anchor, calendar: calendar) }
        case .all:
            let today = calendar.startOfDay(for: now)
            let firstStart = entries.filter { $0.kind == .actual }.map(\.start).min() ?? today
            var day = min(calendar.startOfDay(for: firstStart), today)
            var out: [Date] = []
            while day <= today {
                out.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            return out
        }
    }

    /// Rapport par tâche sur une liste de jours, de la plus longue à la plus courte.
    public static func summaries(_ entries: [Entry], days: [Date], now: Date, shared: Bool = true,
                                 calendar: Calendar = .current) -> [TaskSummary] {
        struct Acc {
            var spellings: [String: TimeInterval] = [:]
            var byCategory: [String: TimeInterval] = [:]
            var perDay: [TaskDay] = []
        }
        var groups: [String: Acc] = [:]
        for day in days {
            for t in DayLogic.taskTotals(entries, on: day, now: now, shared: shared, calendar: calendar) where t.duration > 0 {
                let key = DayLogic.taskKey(t.title)
                var acc = groups[key] ?? Acc()
                acc.spellings[t.title, default: 0] += t.duration       // la graphie la plus utilisée gagne
                acc.byCategory[t.category, default: 0] += t.duration
                acc.perDay.append(TaskDay(day: day, duration: t.duration))
                groups[key] = acc
            }
        }

        // Séances : entrées réelles commencées dans la période, par tâche.
        let rangeStart = days.min().map { calendar.startOfDay(for: $0) }
        let rangeEnd = days.max().flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        var sessions: [String: [Entry]] = [:]
        if let rs = rangeStart, let re = rangeEnd {
            for e in entries where e.kind == .actual && e.start >= rs && e.start < re {
                sessions[DayLogic.taskKey(e.title), default: []].append(e)
            }
        }

        return groups.map { key, g in
            let mine = sessions[key] ?? []
            let main = g.byCategory.max { $0.value < $1.value }!.key
            return TaskSummary(
                key: key, title: g.spellings.max { $0.value < $1.value }!.key, category: main,
                total: g.byCategory.values.reduce(0, +), sessions: mine.count, activeDays: g.perDay.count,
                first: mine.map(\.start).min(), last: mine.map { $0.effectiveEnd(now: now) }.max(),
                perDay: g.perDay.sorted { $0.day < $1.day })
        }
        .sorted { $0.total > $1.total }
    }

    /// Les séances d'une tâche (entrées réelles) sur une liste de jours, de la plus récente à la plus ancienne.
    public static func sessions(of key: String, in entries: [Entry], days: [Date], calendar: Calendar = .current) -> [Entry] {
        guard let first = days.min(), let lastDay = days.max(),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) else { return [] }
        let start = calendar.startOfDay(for: first)
        return entries
            .filter { $0.kind == .actual && DayLogic.taskKey($0.title) == key && $0.start >= start && $0.start < end }
            .sorted { $0.start > $1.start }
    }

    /// Rapport par catégorie sur une liste de jours, de la plus longue à la plus courte.
    public static func categorySummaries(_ entries: [Entry], days: [Date], now: Date, shared: Bool = true,
                                         calendar: Calendar = .current) -> [CategorySummary] {
        struct Acc {
            var perDay: [TaskDay] = []
            var tasks: [String: (spellings: [String: TimeInterval], total: TimeInterval)] = [:]
        }
        var groups: [String: Acc] = [:]
        for day in days {
            for t in DayLogic.taskCategoryTotals(entries, on: day, now: now, shared: shared, calendar: calendar) where t.duration > 0 {
                var acc = groups[t.category] ?? Acc()
                if let last = acc.perDay.last, last.day == day {
                    acc.perDay[acc.perDay.count - 1] = TaskDay(day: day, duration: last.duration + t.duration)
                } else {
                    acc.perDay.append(TaskDay(day: day, duration: t.duration))
                }
                let key = DayLogic.taskKey(t.title)
                var task = acc.tasks[key] ?? (spellings: [:], total: 0)
                task.spellings[t.title, default: 0] += t.duration
                task.total += t.duration
                acc.tasks[key] = task
                groups[t.category] = acc
            }
        }

        // Séances : entrées réelles commencées dans la période, par catégorie.
        let rangeStart = days.min().map { calendar.startOfDay(for: $0) }
        let rangeEnd = days.max().flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        var sessions: [String: [Entry]] = [:]
        if let rs = rangeStart, let re = rangeEnd {
            for e in entries where e.kind == .actual && e.start >= rs && e.start < re { sessions[e.category, default: []].append(e) }
        }

        return groups.map { category, g in
            let mine = sessions[category] ?? []
            return CategorySummary(
                category: category, total: g.perDay.reduce(0) { $0 + $1.duration }, sessions: mine.count, activeDays: g.perDay.count,
                first: mine.map(\.start).min(), last: mine.map { $0.effectiveEnd(now: now) }.max(), perDay: g.perDay.sorted { $0.day < $1.day },
                tasks: g.tasks.values.map { TaskTotal(title: $0.spellings.max { $0.value < $1.value }!.key, category: category, duration: $0.total) }
                    .sorted { $0.duration > $1.duration })
        }
        .sorted { $0.total > $1.total }
    }

    /// Les séances d'une catégorie sur une liste de jours, de la plus récente à la plus ancienne.
    public static func sessions(ofCategory category: String, in entries: [Entry], days: [Date],
                                calendar: Calendar = .current) -> [Entry] {
        guard let first = days.min(), let lastDay = days.max(),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) else { return [] }
        let start = calendar.startOfDay(for: first)
        return entries
            .filter { $0.kind == .actual && $0.category == category && $0.start >= start && $0.start < end }
            .sorted { $0.start > $1.start }
    }
}
