import Foundation

/// Une tâche déjà faite, à relancer en un clic.
public struct TaskRef: Equatable, Sendable {
    public let title: String
    public let category: String
    public init(title: String, category: String) { self.title = title; self.category = category }
}

public enum Recents {
    /// Les dernières tâches distinctes (titre + catégorie de la plus récente), sans celles déjà en cours
    /// ni celles qui sont déjà des raccourcis.
    public static func recent(_ entries: [Entry], limit: Int = 6, now: Date = Date(),
                              excluding presets: [Preset] = Preset.defaults) -> [TaskRef] {
        let excluded = Set(presets.map { DayLogic.taskKey($0.title) })
        let running = Set(entries.filter { $0.kind == .actual && $0.isRunning }.map { DayLogic.taskKey($0.title) })
        let candidates = entries.filter { $0.kind == .actual && $0.start <= now }.sorted { $0.start > $1.start }
        // La graphie la plus utilisée de chaque tâche (à égalité, la plus récente) et la catégorie de sa dernière séance.
        var counts: [String: [String: Int]] = [:]
        for e in candidates { counts[DayLogic.taskKey(e.title), default: [:]][e.title.trimmingCharacters(in: .whitespaces), default: 0] += 1 }
        var seen = Set<String>()
        var out: [TaskRef] = []
        for e in candidates {
            let key = DayLogic.taskKey(e.title)
            guard !key.isEmpty, !excluded.contains(key), !running.contains(key), seen.insert(key).inserted else { continue }
            let spellings = counts[key] ?? [:]
            let best = spellings.values.max() ?? 0
            let recent = e.title.trimmingCharacters(in: .whitespaces)
            let title = (spellings[recent] ?? 0) == best ? recent : (spellings.first { $0.value == best }?.key ?? recent)
            out.append(TaskRef(title: title, category: e.category))
            if out.count == limit { break }
        }
        return out
    }
}
