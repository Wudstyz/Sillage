import Foundation

/// Planifié (rendez-vous prévu) ou réel (ce qui a vraiment été fait).
public enum EntryKind: String, Codable, Sendable {
    case planned
    case actual
}

public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var kind: EntryKind
    public var start: Date
    /// `nil` = la tâche est en cours.
    public var end: Date?

    public init(id: UUID = UUID(), title: String, category: String, kind: EntryKind, start: Date, end: Date? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.kind = kind
        self.start = start
        self.end = end
    }

    public var isRunning: Bool { end == nil }

    /// Fin utilisée pour les calculs : l'heure courante pour une tâche en cours.
    public func effectiveEnd(now: Date) -> Date { end ?? max(now, start) }
}

public enum Categories {
    public static let all = ["Travail", "Repas", "Sommeil", "Santé", "Loisirs", "Hygiène", "Déplacement", "Autre"]
}
