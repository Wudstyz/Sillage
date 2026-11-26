import Foundation

public enum GoalPeriod: String, Codable, CaseIterable, Sendable {
    case day, week, month

    public var reportPeriod: ReportPeriod {
        switch self { case .day: return .day; case .week: return .week; case .month: return .month }
    }
}

public enum GoalKind: String, Codable, Sendable {
    /// « Au moins » : une cible à atteindre (20 h de SFCO par semaine).
    case atLeast
    /// « Au plus » : une limite à ne pas dépasser (5 h de loisirs par jour).
    case atMost
}

/// Un objectif de temps sur une tâche (par titre) ou une catégorie, par jour, semaine ou mois.
public struct Goal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Clé de la tâche visée (`DayLogic.taskKey`), ou `nil` si l'objectif porte sur une catégorie.
    public var taskKey: String?
    public var category: String?
    /// Nom affiché (la tâche ou la catégorie).
    public var title: String
    public var hours: Double
    public var period: GoalPeriod
    public var kind: GoalKind

    public init(id: UUID = UUID(), taskKey: String? = nil, category: String? = nil, title: String, hours: Double,
                period: GoalPeriod, kind: GoalKind = .atLeast) {
        self.id = id
        self.taskKey = taskKey
        self.category = category
        self.title = title
        self.hours = hours
        self.period = period
        self.kind = kind
    }

    public var target: TimeInterval { hours * 3600 }
}

public enum GoalState: Equatable, Sendable {
    case inProgress
    /// « Au moins » atteint.
    case reached
    /// « Au plus » dépassé.
    case exceeded
}

public struct GoalProgress: Equatable, Identifiable, Sendable {
    public var id: UUID { goal.id }
    public let goal: Goal
    public let done: TimeInterval
    public let state: GoalState
    /// Jours restants dans la période (aujourd'hui compris) ; 0 si la période est passée.
    public let daysLeft: Int

    public var fraction: Double { goal.target > 0 ? done / goal.target : 0 }
    public var remaining: TimeInterval { max(0, goal.target - done) }
    /// Pour un objectif « au moins » sur une semaine ou un mois : le temps moyen à faire par jour restant.
    public var perRemainingDay: TimeInterval? {
        goal.kind == .atLeast && goal.period != .day && state == .inProgress && daysLeft > 0 ? remaining / Double(daysLeft) : nil
    }
}

public enum Goals {
    /// Avancement d'un objectif pour la période qui contient `anchor`.
    /// `shared` : le temps simultané est réparti entre les tâches (sinon chaque tâche compte tout son temps).
    public static func progress(_ goal: Goal, entries: [Entry], anchor: Date, now: Date, shared: Bool = true,
                                calendar: Calendar = .current) -> GoalProgress {
        let days = Reports.days(for: goal.period.reportPeriod, anchor: anchor, entries: entries, now: now, calendar: calendar)
        var done: TimeInterval = 0
        for day in days {
            if let key = goal.taskKey {
                done += DayLogic.taskTotals(entries, on: day, now: now, shared: shared, calendar: calendar)
                    .filter { DayLogic.taskKey($0.title) == key }.reduce(0) { $0 + $1.duration }
            } else if let category = goal.category {
                done += DayLogic.totals(entries, on: day, now: now, shared: shared, calendar: calendar)
                    .filter { $0.category == category }.reduce(0) { $0 + $1.duration }
            }
        }
        let state: GoalState
        switch goal.kind {
        case .atLeast: state = done >= goal.target ? .reached : .inProgress
        case .atMost: state = done > goal.target ? .exceeded : .inProgress
        }
        let today = calendar.startOfDay(for: now)
        return GoalProgress(goal: goal, done: done, state: state, daysLeft: days.filter { $0 >= today }.count)
    }

    public static func progress(_ goals: [Goal], entries: [Entry], anchor: Date, now: Date, shared: Bool = true,
                                calendar: Calendar = .current) -> [GoalProgress] {
        goals.map { progress($0, entries: entries, anchor: anchor, now: now, shared: shared, calendar: calendar) }
    }
}
