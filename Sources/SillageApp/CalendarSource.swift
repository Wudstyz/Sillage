import EventKit
import SwiftUI
import SillageCore

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let account: String
    let color: Color
}

/// Lecture (seule) des calendriers du Mac : Calendrier, iCloud, Google, Exchange… tout ce que l'app Calendrier affiche.
/// Optionnel : désactivé par défaut ; l'autorisation de macOS n'est demandée qu'à l'activation.
/// Rien n'est copié dans les données de Sillage ni écrit dans vos calendriers.
@MainActor
final class CalendarSource: ObservableObject {
    enum Access { case unknown, notDetermined, denied, granted }

    @Published private(set) var enabled: Bool
    @Published private(set) var access: Access = .unknown
    @Published private(set) var calendars: [CalendarInfo] = []
    /// Rendez-vous externes de la fenêtre de dates chargée (lecture seule).
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var showAllDay: Bool

    /// SILLAGE_FAKE_CALENDAR : événements fictifs, sans EventKit ni autorisation (tests, captures d'écran).
    private static let fake = ProcessInfo.processInfo.environment["SILLAGE_FAKE_CALENDAR"] != nil
    private let defaults = UserDefaults.standard
    private lazy var store = EKEventStore()
    private var selected: Set<String>?            // nil = tous les calendriers
    private var window: DateInterval?
    private var anchor = Date()
    private var observer: NSObjectProtocol?

    init() {
        if Self.fake {
            enabled = true
            showAllDay = false
            access = .granted
            calendars = [CalendarInfo(id: "perso", title: "Perso", account: "iCloud", color: .teal),
                         CalendarInfo(id: "pro", title: "Travail", account: "Google", color: .blue)]
        } else {
            enabled = defaults.bool(forKey: "calendarsEnabled")
            showAllDay = defaults.bool(forKey: "calendarsAllDay")
            selected = (defaults.array(forKey: "calendarsSelected") as? [String]).map(Set.init)
        }
    }

    /// À appeler au lancement : si l'option était activée, recharge sans rien demander (l'autorisation est déjà donnée ou non).
    func start(anchor: Date) {
        self.anchor = anchor
        guard enabled else { return }
        if Self.fake { reload(around: anchor); return }
        access = currentAccess()
        if access == .granted { refreshCalendars(); reload(around: anchor); watchChanges() }
    }

    // MARK: Activation

    func enable() async {
        if Self.fake { return }
        access = currentAccess()
        if access == .notDetermined {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = (try? await store.requestFullAccessToEvents()) ?? false
            } else {
                granted = await withCheckedContinuation { c in store.requestAccess(to: .event) { ok, _ in c.resume(returning: ok) } }
            }
            access = granted ? .granted : currentAccess()
        }
        guard access == .granted else { return }
        enabled = true
        defaults.set(true, forKey: "calendarsEnabled")
        refreshCalendars()
        reload(around: anchor)
        watchChanges()
    }

    func disable() {
        if Self.fake { return }
        enabled = false
        defaults.set(false, forKey: "calendarsEnabled")
        entries = []
        window = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func currentAccess() -> Access {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined { return .notDetermined }
        if #available(macOS 14.0, *) { return status == .fullAccess ? .granted : .denied }
        return status == .authorized ? .granted : .denied
    }

    private func watchChanges() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshCalendars()
                self.reload(around: self.anchor)
            }
        }
    }

    // MARK: Choix des calendriers

    func isSelected(_ id: String) -> Bool { selected?.contains(id) ?? true }

    func setSelected(_ id: String, _ on: Bool) {
        var set = selected ?? Set(calendars.map(\.id))
        if on { set.insert(id) } else { set.remove(id) }
        selected = set
        if !Self.fake { defaults.set(Array(set), forKey: "calendarsSelected") }
        reload(around: anchor)
    }

    func setShowAllDay(_ on: Bool) {
        showAllDay = on
        if !Self.fake { defaults.set(on, forKey: "calendarsAllDay") }
        reload(around: anchor)
    }

    private func refreshCalendars() {
        guard !Self.fake else { return }
        calendars = store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "",
                                color: Color(nsColor: NSColor(cgColor: $0.cgColor) ?? .gray)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    // MARK: Chargement (fenêtre de ±60 jours autour de la date regardée)

    /// À appeler quand la date affichée change : ne recharge que si on sort de la fenêtre déjà chargée.
    func ensureLoaded(around day: Date) {
        anchor = day
        guard enabled, access == .granted else { return }
        let cal = Calendar.current
        if let w = window,
           let lo = cal.date(byAdding: .day, value: 7, to: w.start), let hi = cal.date(byAdding: .day, value: -7, to: w.end),
           day >= lo, day <= hi { return }
        reload(around: day)
    }

    private func reload(around day: Date) {
        anchor = day
        guard enabled, access == .granted else { return }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -60, to: cal.startOfDay(for: day))!
        let end = cal.date(byAdding: .day, value: 60, to: cal.startOfDay(for: day))!
        window = DateInterval(start: start, end: end)
        if Self.fake { entries = CalendarImport.entries(from: Self.fakeEvents(from: start, to: end), showAllDay: showAllDay); return }
        let chosen = store.calendars(for: .event).filter { isSelected($0.calendarIdentifier) }
        guard !chosen.isEmpty else { entries = []; return }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: chosen))
            .map(Self.convert)
        entries = CalendarImport.entries(from: events, showAllDay: showAllDay)
    }

    private static func convert(_ e: EKEvent) -> ExternalEvent {
        let declined = e.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
        return ExternalEvent(identifier: e.eventIdentifier ?? e.calendarItemIdentifier,
                             calendarID: e.calendar.calendarIdentifier, calendarTitle: e.calendar.title,
                             title: e.title ?? "", start: e.startDate, end: e.endDate,
                             isAllDay: e.isAllDay, isDeclined: declined, isCancelled: e.status == .canceled)
    }

    /// Événements fictifs réguliers (point d'équipe, déjeuner, sport…), pour les tests et les captures.
    private static func fakeEvents(from: Date, to: Date) -> [ExternalEvent] {
        let cal = Calendar.current
        var out: [ExternalEvent] = []
        var day = cal.startOfDay(for: from)
        while day < to {
            let wd = cal.component(.weekday, from: day)          // 1 = dimanche
            func add(_ id: String, _ calendar: String, _ title: String, _ h: Int, _ m: Int, _ minutes: Int) {
                guard let s = cal.date(bySettingHour: h, minute: m, second: 0, of: day) else { return }
                out.append(ExternalEvent(identifier: "\(id)-\(calendar)", calendarID: calendar,
                                         calendarTitle: calendar == "pro" ? "Travail" : "Perso", title: title,
                                         start: s, end: s.addingTimeInterval(Double(minutes) * 60)))
            }
            if (2...6).contains(wd) { add("standup", "pro", "Point d'équipe", 9, 15, 30) }
            if wd == 3 || wd == 5 { add("lunch", "perso", "Déjeuner avec Léa", 12, 30, 90) }
            if wd == 4 { add("dentist", "perso", "Dentiste", 17, 0, 60) }
            if wd == 2 { add("review", "pro", "Revue de projet", 16, 0, 60) }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
