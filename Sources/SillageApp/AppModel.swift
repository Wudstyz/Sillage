import Foundation
import SwiftUI
import SillageCore

enum ViewMode: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var label: String { switch self { case .day: return "Jour"; case .week: return "Semaine"; case .month: return "Mois" } }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var series: [Series] = []
    @Published var day = Date()
    @Published var viewMode: ViewMode = .day {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
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
        // SILLAGE_VIEW : vue affichée au lancement (captures d'écran de la documentation).
        let saved = ProcessInfo.processInfo.environment["SILLAGE_VIEW"] ?? UserDefaults.standard.string(forKey: "viewMode")
        viewMode = ViewMode(rawValue: saved ?? "") ?? .day
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

    /// Période précédente (-1) ou suivante (+1) selon la vue : un jour, une semaine ou un mois.
    func navigate(_ direction: Int) {
        switch viewMode {
        case .day: shift(days: direction)
        case .week: shift(days: 7 * direction)
        case .month: day = Calendar.current.date(byAdding: .month, value: direction, to: day) ?? day
        }
    }

    /// Le jour affiché est-il dans la période en cours (aujourd'hui, cette semaine, ce mois) ?
    var isCurrentPeriod: Bool {
        let cal = Calendar.current
        switch viewMode {
        case .day: return cal.isDateInToday(day)
        case .week: return cal.isDate(day, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return cal.isDate(day, equalTo: Date(), toGranularity: .month)
        }
    }

    /// Ouvre un jour précis dans la vue Jour.
    func open(day: Date) {
        self.day = day
        viewMode = .day
    }

    var periodTitle: String {
        switch viewMode {
        case .day: return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized
        case .week:
            // Court, pour ne pas être tronqué par le sélecteur de vue : « 23 – 29 nov. 2026 » ou « 30 nov. – 6 déc. 2026 ».
            let w = CalendarGrid.week(containing: day)
            let sameMonth = Calendar.current.isDate(w[0], equalTo: w[6], toGranularity: .month)
            let start = sameMonth ? w[0].formatted(.dateTime.day()) : w[0].formatted(.dateTime.day().month(.abbreviated))
            return "\(start) – \(w[6].formatted(.dateTime.day().month(.abbreviated).year()))"
        case .month: return day.formatted(.dateTime.month(.wide).year()).capitalized
        }
    }

    var periodBilanTitle: String {
        switch viewMode { case .day: return "Bilan du jour"; case .week: return "Bilan de la semaine"; case .month: return "Bilan du mois" }
    }

    /// Des tâches se chevauchent-elles sur la période affichée ?
    func periodHasSimultaneous() -> Bool {
        let cal = Calendar.current
        let days: [Date]
        switch viewMode {
        case .day: days = [day]
        case .week: days = CalendarGrid.week(containing: day)
        case .month: days = CalendarGrid.month(containing: day).flatMap { $0 }.filter { cal.isDate($0, equalTo: day, toGranularity: .month) }
        }
        return days.contains { DayLogic.hasSimultaneous(entries, on: $0, now: now) }
    }

    /// Temps passé par catégorie sur la période affichée.
    func periodTotals() -> [(category: String, duration: TimeInterval)] {
        let cal = Calendar.current
        let days: [Date]
        switch viewMode {
        case .day: days = [day]
        case .week: days = CalendarGrid.week(containing: day)
        case .month: days = CalendarGrid.month(containing: day).flatMap { $0 }.filter { cal.isDate($0, equalTo: day, toGranularity: .month) }
        }
        var sums: [String: TimeInterval] = [:]
        for d in days { for t in DayLogic.totals(entries, on: d, now: now) { sums[t.category, default: 0] += t.duration } }
        return sums.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

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
