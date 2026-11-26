import Foundation

/// Une part d'un camembert.
public struct ChartSlice: Equatable, Sendable {
    public let label: String
    /// Catégorie de la part (pour la couleur) ; `nil` pour le regroupement « Autres ».
    public let category: String?
    public let value: TimeInterval
    public var isOther: Bool { category == nil }
}

public enum ChartData {
    public static let otherLabel = "Autres"

    /// Garde les plus grandes parts et regroupe le reste dans « Autres », pour que le camembert reste lisible.
    /// Au plus `maxSlices` parts au total (« Autres » comprise) ; les valeurs nulles sont ignorées.
    public static func slices(_ items: [(label: String, category: String, value: TimeInterval)],
                              maxSlices: Int = 8) -> [ChartSlice] {
        let sorted = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard sorted.count > maxSlices, maxSlices >= 2 else {
            return sorted.map { ChartSlice(label: $0.label, category: $0.category, value: $0.value) }
        }
        let kept = sorted.prefix(maxSlices - 1).map { ChartSlice(label: $0.label, category: $0.category, value: $0.value) }
        let rest = sorted.dropFirst(maxSlices - 1).reduce(0) { $0 + $1.value }
        return kept + [ChartSlice(label: otherLabel, category: nil, value: rest)]
    }
}
