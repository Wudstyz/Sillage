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
    /// Pour une entrée réelle née d'un « J'y suis » : le rendez-vous prévu correspondant.
    public var plannedID: UUID?

    public init(id: UUID = UUID(), title: String, category: String, kind: EntryKind, start: Date, end: Date? = nil,
                plannedID: UUID? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.kind = kind
        self.start = start
        self.end = end
        self.plannedID = plannedID
    }

    public var isRunning: Bool { end == nil }

    /// Fin utilisée pour les calculs : l'heure courante pour une tâche en cours.
    public func effectiveEnd(now: Date) -> Date { end ?? max(now, start) }
}

public enum Categories {
    public static let all = ["Travail", "Repas", "Sommeil", "Santé", "Loisirs", "Hygiène", "Déplacement", "Autre"]
}

/// Activités fréquentes, démarrables en un clic.
public struct Preset: Equatable, Sendable {
    public let title: String
    public let category: String
    public let symbol: String // nom SF Symbols

    public static let defaults: [Preset] = [
        Preset(title: "Douche", category: "Hygiène", symbol: "shower"),
        Preset(title: "Repas", category: "Repas", symbol: "fork.knife"),
        Preset(title: "Sommeil", category: "Sommeil", symbol: "bed.double"),
        Preset(title: "Trajet", category: "Déplacement", symbol: "car"),
        Preset(title: "Pause", category: "Loisirs", symbol: "cup.and.saucer"),
        Preset(title: "Sport", category: "Santé", symbol: "figure.run"),
    ]
}
