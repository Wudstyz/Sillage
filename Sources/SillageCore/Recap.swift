import Foundation

/// Récap d'une journée, calculé à la volée à partir des données : rien à valider, aucune « clôture ».
/// Il est toujours disponible, mis à jour en direct pour aujourd'hui, et valable pour n'importe quel jour passé.

public enum AppointmentStatus: Equatable, Sendable {
    /// « J'y suis » a été utilisé ; le texte dit la ponctualité (« 10 min de retard »).
    case honored(String)
    /// Pas de « J'y suis », mais des activités enregistrées couvrent au moins la moitié du rendez-vous.
    case covered
    /// Terminé sans aucune trace.
    case missed
    case upcoming
    /// Commencé, pas encore honoré.
    case ongoing
}

public struct RecapAppointment: Equatable, Identifiable, Sendable {
    public var id: UUID { entry.id }
    public let entry: Entry
    public let status: AppointmentStatus
}

/// Une plage de la journée : une ou plusieurs activités simultanées, ou un « trou » (rien d'enregistré).
public struct RecapSegment: Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    /// Activités en cours pendant la plage ; vide pour un trou.
    public let entries: [Entry]
    /// La plage touche l'instant présent et une activité y est encore en cours (une plage qui s'est terminée plus tôt,
    /// pendant qu'une autre tâche continuait, n'est pas « en cours »).
    public let isLive: Bool
    public var isGap: Bool { entries.isEmpty }
    public var isRunning: Bool { entries.contains { $0.isRunning } }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Titres distincts (« SFCO + Sillage »).
    public var title: String {
        var seen = Set<String>(), out: [String] = []
        for e in entries where seen.insert(DayLogic.taskKey(e.title)).inserted { out.append(e.title.trimmingCharacters(in: .whitespaces)) }
        return out.joined(separator: " + ")
    }
    public var category: String { entries.first?.category ?? "Autre" }
}

public struct TaskTotal: Equatable, Sendable {
    public let title: String
    public let category: String
    public let duration: TimeInterval
}

public struct DayRecap: Sendable {
    public let day: Date
    public let segments: [RecapSegment]
    public let tasks: [TaskTotal]
    public let categories: [(category: String, duration: TimeInterval)]
    /// Temps réellement écoulé avec au moins une activité (le temps simultané n'est pas compté deux fois).
    public let tracked: TimeInterval
    public let firstStart: Date?
    public let lastEnd: Date?
    public let isStillRunning: Bool
    public let appointments: [RecapAppointment]
    public let hasSimultaneous: Bool

    public var isEmpty: Bool { segments.isEmpty && appointments.isEmpty }
}

public enum Recap {
    /// Les trous plus courts que ça ne sont pas signalés.
    public static let minimumGap: TimeInterval = 5 * 60

    public static func build(_ all: [Entry], on day: Date, now: Date, calendar: Calendar = .current) -> DayRecap {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // Activités réelles du jour, tronquées au jour.
        struct Span { let entry: Entry; let start: Date; let end: Date }
        var spans: [Span] = []
        for e in DayLogic.entries(all, kind: .actual, on: day, now: now, calendar: calendar) {
            let s = max(e.start, dayStart), f = min(e.effectiveEnd(now: now), dayEnd)
            if f > s { spans.append(Span(entry: e, start: s, end: f)) }
        }

        // Balayage : entre deux bornes consécutives, la liste des activités en cours.
        let bounds = Array(Set(spans.flatMap { [$0.start, $0.end] })).sorted()
        var pieces: [(start: Date, end: Date, entries: [Entry])] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            let active = spans.filter { $0.start <= a && $0.end >= b }.map(\.entry).sorted { $0.start < $1.start }
            if let last = pieces.last, last.end == a, last.entries.map(\.id) == active.map(\.id) {
                pieces[pieces.count - 1].end = b                       // même activité : on prolonge
            } else {
                pieces.append((a, b, active))
            }
        }
        let covered = pieces.filter { !$0.entries.isEmpty }
        let segments = pieces
            .filter { !$0.entries.isEmpty || $0.end.timeIntervalSince($0.start) >= minimumGap }
            .map { RecapSegment(start: $0.start, end: $0.end, entries: $0.entries,
                                isLive: $0.end >= min(now, dayEnd) && $0.entries.contains { $0.isRunning }) }

        // Rendez-vous prévus du jour et ce qu'il en est advenu.
        let appointments = all
            .filter { $0.kind == .planned && $0.start >= dayStart && $0.start < dayEnd }
            .sorted { $0.start < $1.start }
            .map { planned -> RecapAppointment in
                RecapAppointment(entry: planned, status: status(of: planned, in: all, covered: covered.map { ($0.start, $0.end) }, now: now))
            }

        let categories = DayLogic.totals(all, on: day, now: now, calendar: calendar)
        return DayRecap(
            day: dayStart, segments: segments,
            tasks: DayLogic.taskTotals(all, on: day, now: now, calendar: calendar).map { TaskTotal(title: $0.title, category: $0.category, duration: $0.duration) },
            categories: categories,
            tracked: categories.reduce(0) { $0 + $1.duration },
            firstStart: spans.map(\.start).min(), lastEnd: spans.map(\.end).max(),
            isStillRunning: spans.contains { $0.entry.isRunning },
            appointments: appointments,
            hasSimultaneous: DayLogic.hasSimultaneous(all, on: day, now: now, calendar: calendar))
    }

    private static func status(of planned: Entry, in all: [Entry], covered: [(Date, Date)], now: Date) -> AppointmentStatus {
        if Actions.isArrived(planned, in: all) {
            let linked = all.first { $0.plannedID == planned.id }
            return .honored(linked.flatMap { Actions.punctuality(of: $0, in: all) } ?? "")
        }
        let end = planned.effectiveEnd(now: now)
        let overlap = covered.reduce(0.0) { $0 + max(0, min($1.1, end).timeIntervalSince(max($1.0, planned.start))) }
        let length = end.timeIntervalSince(planned.start)
        if length > 0, overlap >= length / 2 { return .covered }
        if end <= now { return .missed }
        return planned.start > now ? .upcoming : .ongoing
    }

    // MARK: Texte (copier / partager)

    public static func markdown(_ recap: DayRecap, now: Date) -> String {
        func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
        var lines = ["# " + recap.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized, ""]
        if recap.isEmpty { return lines.joined(separator: "\n") + "Rien d'enregistré ce jour-là.\n" }

        if let first = recap.firstStart, let last = recap.lastEnd {
            let end = recap.isStillRunning ? "maintenant" : time(last)
            lines.append("**Enregistré : \(DayLogic.formatDuration(recap.tracked))** · de \(time(first)) à \(end)")
            lines.append("")
        }
        if !recap.segments.isEmpty {
            lines.append("## Journée")
            for s in recap.segments {
                let range = s.isLive ? "\(time(s.start)) – en cours" : "\(time(s.start)) – \(time(s.end))"
                let what = s.isGap ? "(non renseigné)" : s.title
                lines.append("- \(range) · \(what) · \(DayLogic.formatDuration(s.duration))")
            }
            lines.append("")
        }
        if !recap.tasks.isEmpty {
            lines.append("## Temps par tâche")
            for t in recap.tasks { lines.append("- \(t.title) : \(DayLogic.formatDuration(t.duration))") }
            if recap.hasSimultaneous { lines.append("") ; lines.append("_Tâches simultanées : le temps est réparti entre elles._") }
            lines.append("")
        }
        if !recap.appointments.isEmpty {
            lines.append("## Rendez-vous")
            for a in recap.appointments {
                let state: String
                switch a.status {
                case .honored(let p): state = p.isEmpty ? "honoré" : "honoré (\(p))"
                case .covered: state = "couvert par une activité enregistrée"
                case .missed: state = "sans trace"
                case .upcoming: state = "à venir"
                case .ongoing: state = "en cours, pas encore pointé"
                }
                lines.append("- \(time(a.entry.start)) · \(a.entry.title) : \(state)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
