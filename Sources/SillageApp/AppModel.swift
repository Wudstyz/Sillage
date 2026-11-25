import Foundation
import SwiftUI
import SillageCore

enum ViewMode: String, CaseIterable, Identifiable {
    case day, week, month, tasks, recap
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Jour"; case .week: return "Semaine"; case .month: return "Mois"
        case .tasks: return "Tâches"; case .recap: return "Récap"
        }
    }
}

extension ReportPeriod {
    var label: String {
        switch self { case .day: return "Jour"; case .week: return "Semaine"; case .month: return "Mois"; case .all: return "Tout" }
    }
}

/// État sauvegardé pour annuler / rétablir.
struct Snapshot {
    var entries: [Entry]
    var series: [Series]
}

@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var series: [Series] = []
    @Published var day = Date()
    @Published var viewMode: ViewMode = .day {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    /// Période du rapport de la vue Tâches (jour, semaine, mois, tout).
    @Published var reportPeriod: ReportPeriod = .month {
        didSet { UserDefaults.standard.set(reportPeriod.rawValue, forKey: "reportPeriod") }
    }
    /// Tâche affichée en détail dans la vue Tâches (clé de regroupement).
    @Published var selectedTask: String?
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var now = Date()
    /// Entrée en cours d'édition dans la feuille modale (nouvelle ou existante).
    @Published var editor: EditorTarget?
    @Published var saveError: String?
    /// Message affiché si le fichier de données était illisible au lancement.
    @Published var loadWarning: String?

    private let store: Store
    private var timer: Timer?
    private let notifier = Notifier()
    private var history = UndoStack<Snapshot>()

    init(store: Store = .default) {
        self.store = store
        // SILLAGE_VIEW : vue affichée au lancement (captures d'écran de la documentation).
        let saved = ProcessInfo.processInfo.environment["SILLAGE_VIEW"] ?? UserDefaults.standard.string(forKey: "viewMode")
        viewMode = ViewMode(rawValue: saved ?? "") ?? .day
        reportPeriod = ReportPeriod(rawValue: ProcessInfo.processInfo.environment["SILLAGE_PERIOD"]
                                    ?? UserDefaults.standard.string(forKey: "reportPeriod") ?? "") ?? .month
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

    /// Période effectivement affichée : celle de la vue Jour / Semaine / Mois, ou celle choisie dans la vue Tâches.
    var effectivePeriod: ReportPeriod {
        switch viewMode {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .tasks: return reportPeriod
        case .recap: return .day
        }
    }

    /// Les jours de la période affichée.
    var periodDays: [Date] { Reports.days(for: effectivePeriod, anchor: day, entries: entries, now: now) }

    /// Période précédente (-1) ou suivante (+1) : un jour, une semaine ou un mois (rien pour « tout »).
    func navigate(_ direction: Int) {
        switch effectivePeriod {
        case .day: shift(days: direction)
        case .week: shift(days: 7 * direction)
        case .month: day = Calendar.current.date(byAdding: .month, value: direction, to: day) ?? day
        case .all: break
        }
    }

    /// Le jour affiché est-il dans la période en cours (aujourd'hui, cette semaine, ce mois) ?
    var isCurrentPeriod: Bool {
        let cal = Calendar.current
        switch effectivePeriod {
        case .day: return cal.isDateInToday(day)
        case .week: return cal.isDate(day, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return cal.isDate(day, equalTo: Date(), toGranularity: .month)
        case .all: return true
        }
    }

    /// Ouvre un jour précis dans la vue Jour.
    func open(day: Date) {
        self.day = day
        viewMode = .day
    }

    /// Ouvre une tâche en détail dans la vue Tâches.
    func openTask(_ title: String) {
        selectedTask = DayLogic.taskKey(title)
        viewMode = .tasks
    }

    var periodTitle: String {
        let base: String
        switch effectivePeriod {
        case .day: base = day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized
        case .week:
            // Court, pour ne pas être tronqué par le sélecteur de vue : « 23 – 29 nov. 2026 » ou « 30 nov. – 6 déc. 2026 ».
            let w = CalendarGrid.week(containing: day)
            let sameMonth = Calendar.current.isDate(w[0], equalTo: w[6], toGranularity: .month)
            let start = sameMonth ? w[0].formatted(.dateTime.day()) : w[0].formatted(.dateTime.day().month(.abbreviated))
            base = "\(start) – \(w[6].formatted(.dateTime.day().month(.abbreviated).year()))"
        case .month: base = day.formatted(.dateTime.month(.wide).year()).capitalized
        case .all: base = "Tout l'historique"
        }
        switch viewMode {
        case .tasks: return "Tâches · \(base)"
        case .recap: return "Récap · " + day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        default: return base
        }
    }

    var periodBilanTitle: String {
        switch effectivePeriod {
        case .day: return "Bilan du jour"
        case .week: return "Bilan de la semaine"
        case .month: return "Bilan du mois"
        case .all: return "Bilan global"
        }
    }

    /// Des tâches se chevauchent-elles sur la période affichée ?
    func periodHasSimultaneous() -> Bool {
        periodDays.contains { DayLogic.hasSimultaneous(entries, on: $0, now: now) }
    }

    /// Temps passé par catégorie sur la période affichée.
    func periodTotals() -> [(category: String, duration: TimeInterval)] {
        var sums: [String: TimeInterval] = [:]
        for d in periodDays { for t in DayLogic.totals(entries, on: d, now: now) { sums[t.category, default: 0] += t.duration } }
        return sums.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// Rapport par tâche sur la période affichée.
    func taskSummaries() -> [TaskSummary] { Reports.summaries(entries, days: periodDays, now: now) }

    /// Temps passé par tâche sur la période affichée (pour le bilan de la barre latérale).
    func periodTaskTotals() -> [(title: String, category: String, duration: TimeInterval)] {
        taskSummaries().map { ($0.title, $0.category, $0.total) }
    }

    /// Tâches récentes, relançables en un clic.
    var recents: [TaskRef] { Recents.recent(entries, now: now) }

    // MARK: Actions

    /// « Je commence maintenant » : une tâche réelle sans fin.
    /// Réglage partagé avec la case de la barre latérale (par défaut : activé).
    var stopRunningOnStart: Bool { UserDefaults.standard.object(forKey: "stopRunningOnStart") as? Bool ?? true }

    /// « Je commence maintenant » : une tâche réelle sans fin.
    func start(title: String, category: String, stopRunning: Bool? = nil) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        now = Date()
        commit {
            entries = Actions.startTask(entries, title: t, category: category, now: now,
                                        stopRunning: stopRunning ?? stopRunningOnStart)
        }
    }

    /// « J'y suis » : démarre maintenant la tâche réelle liée à ce rendez-vous.
    func arrive(at planned: Entry) {
        now = Date()
        commit { entries = Actions.arrive(entries, at: planned.id, now: now, stopRunning: stopRunningOnStart) }
        day = Date()
    }

    func isArrived(_ planned: Entry) -> Bool { Actions.isArrived(planned, in: entries) }
    func punctuality(of e: Entry) -> String? { Actions.punctuality(of: e, in: entries) }

    func stop(_ id: UUID) {
        now = Date()
        guard entries.contains(where: { $0.id == id }) else { return }
        commit {
            guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[i].end = max(now, entries[i].start)
        }
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
        commit {
            var e = entry
            if let rule = recurrence, e.kind == .planned, e.seriesID == nil {
                // L'entrée devient la première occurrence ; les suivantes sont générées à l'avance.
                let made = Series.make(from: e, rule: rule)
                e = made.first
                series.append(made.series)
            }
            if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
            Series.topUp(&series, entries: &entries, now: Date())
        }
    }

    func series(of entry: Entry) -> Series? { entry.seriesID.flatMap { id in series.first { $0.id == id } } }

    func delete(_ id: UUID) {
        commit { entries.removeAll { $0.id == id } }
    }

    /// Supprime ce rendez-vous et tous les suivants de sa série (les occurrences déjà vécues restent).
    func deleteFollowing(_ entry: Entry) {
        guard let id = entry.seriesID else { return delete(entry.id) }
        commit { Series.end(id, from: entry.start, series: &series, entries: &entries) }
    }

    // MARK: Annuler / rétablir

    private var snapshot: Snapshot { Snapshot(entries: entries, series: series) }

    /// Applique une modification en mémorisant l'état d'avant, pour pouvoir l'annuler.
    private func commit(_ change: () -> Void) {
        history.record(snapshot)
        change()
        persist()
        refreshHistoryFlags()
    }

    func undo() {
        guard let previous = history.undo(current: snapshot) else { return }
        restore(previous)
    }

    func redo() {
        guard let next = history.redo(current: snapshot) else { return }
        restore(next)
    }

    private func restore(_ state: Snapshot) {
        entries = state.entries
        series = state.series
        persist()
        refreshHistoryFlags()
    }

    private func refreshHistoryFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    private func persist() {
        do { try store.save(entries, series: series) } catch { saveError = error.localizedDescription }
        notifier.reschedule(entries, now: Date())
    }
}
