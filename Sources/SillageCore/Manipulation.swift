import Foundation

/// Gestes sur la frise : aimantation au quart d'heure, déplacement, étirement, sélection d'une plage.
public enum Manipulation {
    public static let step: TimeInterval = 15 * 60

    /// Arrondit à la graduation la plus proche.
    public static func snap(_ date: Date, step: TimeInterval = Manipulation.step) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded() * step)
    }

    /// Plage sélectionnée en glissant de `a` à `b` (dans n'importe quel sens) : alignée, d'au moins un pas.
    public static func range(_ a: Date, _ b: Date, step: TimeInterval = Manipulation.step) -> (start: Date, end: Date) {
        let lo = snap(min(a, b), step: step), hi = snap(max(a, b), step: step)
        return hi > lo ? (lo, hi) : (lo, lo.addingTimeInterval(step))
    }

    /// Déplace une entrée terminée en gardant sa durée ; une entrée entièrement dans `bounds` y reste.
    /// Une tâche en cours n'est pas déplaçable.
    public static func moved(_ e: Entry, by delta: TimeInterval, within bounds: DateInterval? = nil) -> Entry {
        guard let end = e.end else { return e }
        let duration = end.timeIntervalSince(e.start)
        var start = snap(e.start.addingTimeInterval(delta))
        if let b = bounds, e.start >= b.start, end <= b.end {
            start = max(start, b.start)
            if start.addingTimeInterval(duration) > b.end { start = b.end.addingTimeInterval(-duration) }
        }
        var r = e
        r.start = start
        r.end = start.addingTimeInterval(duration)
        return r
    }

    /// Déplace la fin d'une entrée terminée (au moins un pas de durée). Une tâche en cours n'a pas de fin à étirer.
    public static func resized(_ e: Entry, by delta: TimeInterval, within bounds: DateInterval? = nil) -> Entry {
        guard let end = e.end else { return e }
        var newEnd = snap(end.addingTimeInterval(delta))
        if let b = bounds, end <= b.end { newEnd = min(newEnd, b.end) }
        newEnd = max(newEnd, e.start.addingTimeInterval(step))
        var r = e
        r.end = newEnd
        return r
    }
}
