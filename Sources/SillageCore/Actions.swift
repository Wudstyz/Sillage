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
}
