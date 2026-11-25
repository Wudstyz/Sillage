import Foundation
import SwiftUI
import SillageCore

@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var series: [Series] = []
    @Published var day = Date()
    @Published var now = Date()
    /// Entrée en cours d'édition dans la feuille modale (nouvelle ou existante).
    @Published var editor: EditorTarget?
    @Published var saveError: String?
    /// Message affiché si le fichier de données était illisible au lancement.
    @Published var loadWarning: String?

    private let store: Store
    private var timer: Timer?
    private let notifier = Notifier()

    init(store: Store = .default) {
        self.store = store
        let loaded = store.load()
        entries = loaded.entries
        series = loaded.series
        if let aside = loaded.quarantinedAt {
            loadWarning = "Le fichier de données était illisible. Il a été conservé tel quel (\(aside.lastPathComponent), dans \(aside.deletingLastPathComponent().path)) et Sillage repart d'une journée vide."
        }
        if Series.topUp(&series, entries: &entries, now: Date()) { persist() } else { notifier.reschedule(entries, now: Date()) }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        // Prolonge les séries au fil du temps (un an d'avance) et reprogramme les rappels.
        if Series.topUp(&series, entries: &entries, now: now) { persist() }
    }

    struct EditorTarget: Identifiable {
        let id = UUID()
        var entry: Entry
        var isNew: Bool
    }

    var running: [Entry] { entries.filter { $0.kind == .actual && $0.isRunning }.sorted { $0.start < $1.start } }
    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func shift(days: Int) { day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day }

    // MARK: Actions

    /// « Je commence maintenant » : une tâche réelle sans fin.
    /// Réglage partagé avec la case de la barre latérale (par défaut : activé).
    var stopRunningOnStart: Bool { UserDefaults.standard.object(forKey: "stopRunningOnStart") as? Bool ?? true }

    /// « Je commence maintenant » : une tâche réelle sans fin.
    func start(title: String, category: String, stopRunning: Bool? = nil) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        now = Date()
        entries = Actions.startTask(entries, title: t, category: category, now: now,
                                    stopRunning: stopRunning ?? stopRunningOnStart)
        persist()
    }

    /// « J'y suis » : démarre maintenant la tâche réelle liée à ce rendez-vous.
    func arrive(at planned: Entry) {
        now = Date()
        entries = Actions.arrive(entries, at: planned.id, now: now, stopRunning: stopRunningOnStart)
        day = Date()
        persist()
    }

    func isArrived(_ planned: Entry) -> Bool { Actions.isArrived(planned, in: entries) }
    func punctuality(of e: Entry) -> String? { Actions.punctuality(of: e, in: entries) }

    func stop(_ id: UUID) {
        now = Date()
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].end = max(now, entries[i].start)
        persist()
    }

    /// Ouvre la fiche d'une tâche oubliée avec une fin à renseigner (par défaut : maintenant).
    func fixEnd(of entry: Entry) {
        var e = entry
        e.end = max(Date(), entry.start.addingTimeInterval(60))
        editor = EditorTarget(entry: e, isNew: false)
    }

    func newPlanned() -> EditorTarget {
        let base = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        return EditorTarget(entry: Entry(title: "", category: "Santé", kind: .planned, start: base,
                                         end: base.addingTimeInterval(3600)), isNew: true)
    }

    func newPast() -> EditorTarget {
        let base = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return EditorTarget(entry: Entry(title: "", category: "Repas", kind: .actual, start: base,
                                         end: base.addingTimeInterval(3600)), isNew: true)
    }

    func save(_ entry: Entry, recurrence: Recurrence? = nil) {
        var e = entry
        if let rule = recurrence, e.kind == .planned, e.seriesID == nil {
            // L'entrée devient la première occurrence ; les suivantes sont générées à l'avance.
            let made = Series.make(from: e, rule: rule)
            e = made.first
            series.append(made.series)
        }
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        Series.topUp(&series, entries: &entries, now: Date())
        persist()
    }

    func series(of entry: Entry) -> Series? { entry.seriesID.flatMap { id in series.first { $0.id == id } } }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Supprime ce rendez-vous et tous les suivants de sa série (les occurrences déjà vécues restent).
    func deleteFollowing(_ entry: Entry) {
        guard let id = entry.seriesID else { return delete(entry.id) }
        Series.end(id, from: entry.start, series: &series, entries: &entries)
        persist()
    }

    private func persist() {
        do { try store.save(entries, series: series) } catch { saveError = error.localizedDescription }
        notifier.reschedule(entries, now: Date())
    }
}
