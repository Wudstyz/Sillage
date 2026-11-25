import Foundation

/// Grilles de dates pour les vues semaine et mois.
public enum CalendarGrid {
    /// Les 7 jours (début de journée) de la semaine contenant `date`, selon le premier jour de la semaine du calendrier.
    public static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// Les semaines (lignes de 7 jours) qui couvrent le mois de `date`, jours des mois voisins compris.
    public static func month(containing date: Date, calendar: Calendar = .current) -> [[Date]] {
        let monthInterval = calendar.dateInterval(of: .month, for: date)!
        let first = week(containing: monthInterval.start, calendar: calendar)[0]
        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)!
        let last = week(containing: lastDay, calendar: calendar)[6]
        let count = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first)! }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    public static func isSameMonth(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }
}
