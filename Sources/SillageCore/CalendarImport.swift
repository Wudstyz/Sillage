import Foundation
import CryptoKit

/// Un événement lu dans un calendrier du Mac (Calendrier, iCloud, Google, Exchange…), indépendant d'EventKit.
public struct ExternalEvent: Equatable, Sendable {
    public let identifier: String
    public let calendarID: String
    public let calendarTitle: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let isCancelled: Bool

    public init(identifier: String, calendarID: String, calendarTitle: String, title: String, start: Date, end: Date,
                isAllDay: Bool = false, isDeclined: Bool = false, isCancelled: Bool = false) {
        self.identifier = identifier; self.calendarID = calendarID; self.calendarTitle = calendarTitle
        self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.isDeclined = isDeclined; self.isCancelled = isCancelled
    }
}

/// Transforme des événements de calendrier en rendez-vous « Prévu » en lecture seule.
public enum CalendarImport {
    /// Catégorie des rendez-vous venus d'un calendrier externe.
    public static let category = "Calendrier"

    /// Identifiant stable d'une occurrence (un événement récurrent a le même identifiant à chaque occurrence :
    /// on y ajoute la date de début). Il sert à relier un « J'y suis » à son rendez-vous d'un lancement à l'autre.
    public static func stableID(identifier: String, start: Date) -> UUID {
        let digest = SHA256.hash(data: Data("\(identifier)|\(Int(start.timeIntervalSince1970))".utf8))
        let b = Array(digest.prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// `selectedCalendars` : `nil` = tous les calendriers. Les événements refusés, annulés (et, sauf `showAllDay`,
    /// « toute la journée ») sont ignorés. Une fin avant le début devient 30 minutes.
    public static func entries(from events: [ExternalEvent], selectedCalendars: Set<String>? = nil,
                               showAllDay: Bool = false) -> [Entry] {
        events.compactMap { e -> Entry? in
            guard !e.isDeclined, !e.isCancelled, showAllDay || !e.isAllDay,
                  selectedCalendars.map({ $0.contains(e.calendarID) }) ?? true else { return nil }
            let end = e.end > e.start ? e.end : e.start.addingTimeInterval(30 * 60)
            return Entry(id: stableID(identifier: e.identifier, start: e.start),
                         title: e.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Sans titre" : e.title,
                         category: category, kind: .planned, start: e.start, end: end, source: e.calendarTitle)
        }
        .sorted { $0.start < $1.start }
    }
}
