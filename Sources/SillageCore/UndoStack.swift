import Foundation

/// Historique pour annuler / rétablir : on enregistre l'état *avant* chaque modification.
public struct UndoStack<State> {
    private var past: [State] = []
    private var future: [State] = []
    public let limit: Int

    public init(limit: Int = 50) { self.limit = limit }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// À appeler avant une modification : mémorise l'état courant et efface les « rétablir ».
    public mutating func record(_ current: State) {
        past.append(current)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    /// Renvoie l'état à restaurer (et garde `current` pour pouvoir rétablir).
    public mutating func undo(current: State) -> State? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(current: State) -> State? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}
