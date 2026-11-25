import Foundation

/// Actions sur la liste d'entrées, sans interface (donc testables).
public enum Actions {
    /// Démarre une tâche réelle à `now`. `stopRunning` termine au même instant les tâches en cours.
    public static func startTask(_ entries: [Entry], title: String, category: String, plannedID: UUID? = nil,
                                 now: Date, stopRunning: Bool) -> [Entry] {
        var list = entries
        if stopRunning {
            for i in list.indices where list[i].kind == .actual && list[i].isRunning {
                list[i].end = max(now, list[i].start)
            }
        }
        list.append(Entry(title: title, category: category, kind: .actual, start: now, plannedID: plannedID))
        return list
    }

    /// « J'y suis » : démarre la tâche réelle correspondant à un rendez-vous prévu.
    /// Sans effet si le rendez-vous n'existe pas, n'est pas « prévu », ou a déjà son entrée réelle.
    public static func arrive(_ entries: [Entry], at plannedID: UUID, now: Date, stopRunning: Bool) -> [Entry] {
        guard let planned = entries.first(where: { $0.id == plannedID && $0.kind == .planned }),
              !isArrived(planned, in: entries) else { return entries }
        return startTask(entries, title: planned.title, category: planned.category, plannedID: planned.id,
                         now: now, stopRunning: stopRunning)
    }

    public static func isArrived(_ planned: Entry, in entries: [Entry]) -> Bool {
        entries.contains { $0.plannedID == planned.id }
    }

    /// Ponctualité d'une entrée réelle par rapport à son rendez-vous prévu ; `nil` si elle n'en a pas.
    public static func punctuality(of actual: Entry, in entries: [Entry]) -> String? {
        guard let pid = actual.plannedID, let planned = entries.first(where: { $0.id == pid }) else { return nil }
        let m = Int((actual.start.timeIntervalSince(planned.start) / 60).rounded())
        if m == 0 { return "à l'heure" }
        return m > 0 ? "\(m) min de retard" : "\(-m) min d'avance"
    }

    /// Prochain rendez-vous prévu pas encore honoré : à venir, ou déjà commencé et non terminé (donc en retard).
    public static func nextPlanned(_ entries: [Entry], now: Date) -> Entry? {
        entries
            .filter { $0.kind == .planned && !isArrived($0, in: entries) && $0.effectiveEnd(now: now) > now }
            .min { $0.start < $1.start }
    }

    /// « dans 25 min » / « en retard de 10 min » pour un rendez-vous prévu.
    public static func countdown(to planned: Entry, now: Date) -> String {
        let m = Int((planned.start.timeIntervalSince(now) / 60).rounded())
        if m > 0 { return "dans \(DayLogic.formatDuration(TimeInterval(m * 60)))" }
        return m == 0 ? "maintenant" : "commencé il y a \(DayLogic.formatDuration(TimeInterval(-m * 60)))"
    }

    /// Nombre de séances réelles d'une tâche (titres identiques à la casse, aux accents et aux espaces près).
    public static func sessionCount(_ entries: [Entry], key: String) -> Int {
        entries.filter { $0.kind == .actual && DayLogic.taskKey($0.title) == key }.count
    }

    /// Renomme toutes les séances réelles d'une tâche ; si le nouveau nom est celui d'une autre tâche, elles fusionnent.
    /// `category` : si elle est donnée, toutes les séances passent dans cette catégorie. Les rendez-vous prévus ne changent pas.
    public static func renameTask(_ entries: [Entry], key: String, to newTitle: String,
                                  category: String? = nil) -> (entries: [Entry], changed: Int) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return (entries, 0) }
        var list = entries
        var changed = 0
        for i in list.indices where list[i].kind == .actual && DayLogic.taskKey(list[i].title) == key {
            var e = list[i]
            e.title = title
            if let category { e.category = category }
            if e != list[i] { changed += 1 }
            list[i] = e
        }
        return (list, changed)
    }
}
