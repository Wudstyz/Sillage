import XCTest
@testable import SillageCore

final class SillageCoreTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    var day: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 25))! }

    func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(byAdding: .minute, value: h * 60 + m, to: day)! }

    func entry(_ title: String, _ s: Date, _ e: Date?, _ kind: EntryKind = .actual, _ cat: String = "Autre") -> Entry {
        Entry(title: title, category: cat, kind: kind, start: s, end: e)
    }

    func testFormatDuration() {
        XCTAssertEqual(DayLogic.formatDuration(45 * 60), "45 min")
        XCTAssertEqual(DayLogic.formatDuration(95 * 60), "1 h 35")
    }

    func testEntriesForDayIncludesRunningAndExcludesOtherDays() {
        let now = at(17)
        let list = [
            entry("a", at(8), at(9)),
            entry("b", at(16, 34), nil),
            entry("c", at(-3), at(-1)),
        ]
        XCTAssertEqual(DayLogic.entries(list, on: day, now: now, calendar: cal).map(\.title), ["a", "b"])
    }

    func testOverlappingEntriesGoSideBySide() {
        let now = at(18)
        let placed = DayLogic.lanes([
            entry("a", at(9), at(11)), entry("b", at(10), at(12)), entry("c", at(13), at(14)),
        ], now: now)
        XCTAssertEqual(placed.map { [$0.entry.title, "\($0.lane)", "\($0.lanes)"] },
                       [["a", "0", "2"], ["b", "1", "2"], ["c", "0", "1"]])
    }

    func testTotalsClipToDayAndIgnorePlanned() {
        let now = at(18)
        let list = [
            entry("nuit", at(-2), at(7), .actual, "Sommeil"),      // 7 h sur ce jour
            entry("rdv", at(10), at(11), .planned, "Santé"),        // prévu : ignoré
            entry("projet", at(16, 34), nil, .actual, "Travail"),   // en cours jusqu'à 18 h
        ]
        let t = DayLogic.totals(list, on: day, now: now, calendar: cal)
        XCTAssertEqual(t.map(\.category), ["Sommeil", "Travail"])
        XCTAssertEqual(t[0].duration, 7 * 3600)
        XCTAssertEqual(t[1].duration, 86 * 60)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sillage-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = Store(url: url)
        XCTAssertEqual(store.load().entries, [])
        let e = Entry(title: "Médecin", category: "Santé", kind: .planned, start: at(10), end: at(11))
        try store.save([e])
        XCTAssertEqual(store.load().entries, [e])
    }

    func testCorruptFileIsQuarantinedNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sillage-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("data.json")
        try Data("{ pas du json".utf8).write(to: url)
        let store = Store(url: url)
        let r = store.load()
        XCTAssertEqual(r.entries, [])
        let aside = try XCTUnwrap(r.quarantinedAt)
        XCTAssertEqual(try String(contentsOf: aside), "{ pas du json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try store.save([])  // la sauvegarde suivante n'écrase pas l'original
        XCTAssertEqual(try String(contentsOf: aside), "{ pas du json")
    }

    func testDailyBackupKeepsOnlyRecent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sillage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(url: dir.appendingPathComponent("data.json"))
        try store.save([])                       // crée le fichier
        for d in 0..<20 { store.backupIfNeeded(now: at(0).addingTimeInterval(Double(d) * 86400), keep: 14) }
        let files = try FileManager.default.contentsOfDirectory(atPath: store.backupsDirectory.path)
        XCTAssertEqual(files.count, 14)
    }

    func testForgottenTask() {
        let running = entry("x", at(2), nil)
        XCTAssertFalse(DayLogic.isLikelyForgotten(running, now: at(13)))
        XCTAssertTrue(DayLogic.isLikelyForgotten(running, now: at(14)))
        XCTAssertFalse(DayLogic.isLikelyForgotten(entry("y", at(2), at(3)), now: at(20)))
    }

    func testStartTaskStopsRunningOnlyWhenAsked() {
        let running = entry("douche", at(7), nil)
        let kept = Actions.startTask([running], title: "repas", category: "Repas", now: at(8), stopRunning: false)
        XCTAssertNil(kept[0].end)
        let switched = Actions.startTask([running], title: "repas", category: "Repas", now: at(8), stopRunning: true)
        XCTAssertEqual(switched[0].end, at(8))
        XCTAssertEqual(switched[1].start, at(8))
        XCTAssertNil(switched[1].end)
    }

    func testArriveCreatesLinkedEntryOnce() {
        let rdv = entry("Médecin", at(9), at(10), .planned, "Santé")
        let once = Actions.arrive([rdv], at: rdv.id, now: at(9, 10), stopRunning: true)
        XCTAssertEqual(once.count, 2)
        XCTAssertEqual(once[1].plannedID, rdv.id)
        XCTAssertEqual(once[1].category, "Santé")
        XCTAssertEqual(Actions.arrive(once, at: rdv.id, now: at(9, 20), stopRunning: true).count, 2) // pas de doublon
        XCTAssertEqual(Actions.arrive(once, at: once[1].id, now: at(9, 20), stopRunning: true).count, 2) // pas un « prévu »
        XCTAssertTrue(Actions.isArrived(rdv, in: once))
    }

    func testPunctuality() {
        let rdv = entry("Médecin", at(9), at(10), .planned)
        var a = Entry(title: "Médecin", category: "Santé", kind: .actual, start: at(9, 10), plannedID: rdv.id)
        XCTAssertEqual(Actions.punctuality(of: a, in: [rdv, a]), "10 min de retard")
        a.start = at(8, 55); XCTAssertEqual(Actions.punctuality(of: a, in: [rdv, a]), "5 min d'avance")
        a.start = at(9); XCTAssertEqual(Actions.punctuality(of: a, in: [rdv, a]), "à l'heure")
        XCTAssertNil(Actions.punctuality(of: entry("x", at(9), nil), in: []))
    }

    func testOldFilesWithoutPlannedIDStillDecode() throws {
        let json = #"{"entries":[{"id":"6F0B9C1E-0000-4000-8000-000000000001","title":"a","category":"Autre","kind":"actual","start":"2026-11-25T08:00:00Z"}]}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sillage-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        let r = Store(url: url).load()
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertNil(r.entries[0].plannedID)
    }

    func testSnapAndRange() {
        XCTAssertEqual(Manipulation.snap(at(9, 7)), at(9, 0))
        XCTAssertEqual(Manipulation.snap(at(9, 8)), at(9, 15))
        let r = Manipulation.range(at(11, 40), at(10, 2))           // sens inverse
        XCTAssertEqual(r.start, at(10, 0)); XCTAssertEqual(r.end, at(11, 45))
        let tiny = Manipulation.range(at(10, 1), at(10, 3))         // un simple clic : un pas minimum
        XCTAssertEqual(tiny.end.timeIntervalSince(tiny.start), 900)
    }

    func testMoveKeepsDurationAndStaysInDay() {
        let dayBounds = DateInterval(start: day, end: day.addingTimeInterval(86400))
        let e = entry("a", at(9), at(10, 30))
        let m = Manipulation.moved(e, by: 3600 + 400, within: dayBounds)        // +1 h 6 min → aimanté
        XCTAssertEqual(m.start, at(10, 0)); XCTAssertEqual(m.end, at(11, 30))
        let top = Manipulation.moved(e, by: -20 * 3600, within: dayBounds)       // trop haut : bloqué à minuit
        XCTAssertEqual(top.start, at(0)); XCTAssertEqual(top.end, at(1, 30))
        let bottom = Manipulation.moved(e, by: 20 * 3600, within: dayBounds)
        XCTAssertEqual(bottom.end, at(24))
        let run = entry("run", at(9), nil)
        XCTAssertEqual(Manipulation.moved(run, by: 3600), run)                   // en cours : intact
    }

    func testResize() {
        let e = entry("a", at(9), at(10))
        XCTAssertEqual(Manipulation.resized(e, by: 1800).end, at(10, 30))
        XCTAssertEqual(Manipulation.resized(e, by: -7200).end, at(9, 15))       // durée minimale d'un pas
        XCTAssertNil(Manipulation.resized(entry("run", at(9), nil), by: 1800).end)  // en cours : intact
    }

    func testNextPlannedAndCountdown() {
        let past = entry("passé", at(8), at(9), .planned)
        let late = entry("en cours de retard", at(10), at(11), .planned)
        let later = entry("plus tard", at(14), at(15), .planned)
        let now = at(10, 20)
        XCTAssertEqual(Actions.nextPlanned([later, past, late], now: now)?.title, "en cours de retard")
        XCTAssertEqual(Actions.countdown(to: late, now: now), "commencé il y a 20 min")
        XCTAssertEqual(Actions.countdown(to: later, now: now), "dans 3 h 40")
        let arrived = Entry(title: "x", category: "Autre", kind: .actual, start: at(10, 5), plannedID: late.id)
        XCTAssertEqual(Actions.nextPlanned([later, late, arrived], now: now)?.title, "plus tard")
        XCTAssertNil(Actions.nextPlanned([past], now: now))
    }

    // MARK: Récurrence et rappels

    /// Calendrier fixe (UTC, semaine commençant le lundi) pour des tests déterministes.
    var fixed: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        fixed.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
    }
    func rdv(_ start: Date) -> Entry { Entry(title: "Kiné", category: "Santé", kind: .planned, start: start, end: start.addingTimeInterval(3600)) }

    func testWeeklyOnChosenWeekdays() {
        // lundi 2 novembre 2026 ; lundis et mercredis (weekday : 2 et 4)
        let first = rdv(d(2026, 11, 2))
        let (s, _) = Series.make(from: first, rule: Recurrence(frequency: .weekly, weekdays: [2, 4]), calendar: fixed)
        let days = s.occurrences(from: d(2026, 11, 3), through: d(2026, 11, 16), calendar: fixed).map { fixed.component(.day, from: $0.start) }
        XCTAssertEqual(days, [4, 9, 11, 16])
    }

    func testEveryTwoWeeksAndUntil() {
        let (s, _) = Series.make(from: rdv(d(2026, 11, 2)), rule: Recurrence(frequency: .weekly, interval: 2, until: d(2026, 12, 14)), calendar: fixed)
        let days = s.occurrences(from: d(2026, 11, 3), through: d(2027, 1, 31), calendar: fixed).map { fixed.component(.day, from: $0.start) }
        XCTAssertEqual(days, [16, 30, 14])      // 16 nov, 30 nov, 14 déc, puis plus rien après « jusqu'au »
    }

    func testMonthlyOn31StaysOnLastDay() {
        let (s, _) = Series.make(from: rdv(d(2026, 1, 31)), rule: Recurrence(frequency: .monthly), calendar: fixed)
        let days = s.occurrences(from: d(2026, 2, 1), through: d(2026, 4, 30), calendar: fixed).map { fixed.component(.day, from: $0.start) }
        XCTAssertEqual(days, [28, 31, 30])      // février, mars, avril
    }

    func testOccurrencesKeepTimeAndDuration() {
        let (s, _) = Series.make(from: rdv(d(2026, 11, 2, 14, 30)), rule: Recurrence(frequency: .daily), calendar: fixed)
        let o = s.occurrences(from: d(2026, 11, 3), through: d(2026, 11, 3), calendar: fixed)[0]
        XCTAssertEqual(o.start, d(2026, 11, 3, 14, 30)); XCTAssertEqual(o.end, d(2026, 11, 3, 15, 30))
        XCTAssertEqual(o.seriesID, s.id)
    }

    func testTopUpDoesNotDuplicateNorRecreateDeleted() {
        let now = d(2026, 11, 2, 8)
        let (s, first) = Series.make(from: rdv(d(2026, 11, 2)), rule: Recurrence(frequency: .daily), calendar: fixed)
        var series = [s]; var entries = [first]
        Series.topUp(&series, entries: &entries, now: now, horizonDays: 10, calendar: fixed)
        XCTAssertEqual(entries.count, 11)                                   // jour 0 à jour 10
        entries.removeAll { $0.start == d(2026, 11, 5) }                    // l'utilisateur supprime une occurrence
        XCTAssertFalse(Series.topUp(&series, entries: &entries, now: now, horizonDays: 10, calendar: fixed))
        Series.topUp(&series, entries: &entries, now: d(2026, 11, 5, 8), horizonDays: 10, calendar: fixed)
        XCTAssertEqual(entries.count, 13)                                   // 10 restants + les 13, 14 et 15 ; le 5 n'est pas recréé
        XCTAssertFalse(entries.contains { $0.start == d(2026, 11, 5) })
    }

    func testEndSeriesKeepsLivedOccurrences() {
        let now = d(2026, 11, 2, 8)
        let (s, first) = Series.make(from: rdv(d(2026, 11, 2)), rule: Recurrence(frequency: .daily), calendar: fixed)
        var series = [s]; var entries = [first]
        Series.topUp(&series, entries: &entries, now: now, horizonDays: 6, calendar: fixed)
        let done = entries.first { $0.start == d(2026, 11, 5) }!
        entries = Actions.arrive(entries, at: done.id, now: d(2026, 11, 5, 9), stopRunning: false)
        let cutoff = entries.first { $0.start == d(2026, 11, 4) }!
        Series.end(s.id, from: cutoff.start, series: &series, entries: &entries, calendar: fixed)
        let planned = entries.filter { $0.kind == .planned }.map { fixed.component(.day, from: $0.start) }.sorted()
        XCTAssertEqual(planned, [2, 3, 5])                                  // le 5 est resté : déjà vécu
        XCTAssertEqual(series[0].rule.until, d(2026, 11, 3, 0))
        Series.topUp(&series, entries: &entries, now: d(2026, 11, 20), horizonDays: 10, calendar: fixed)
        XCTAssertEqual(entries.filter { $0.kind == .planned }.count, 3)     // rien de plus généré
        Series.end(s.id, from: first.start, series: &series, entries: &entries, calendar: fixed)
        XCTAssertTrue(series.isEmpty)                                       // début atteint : série supprimée
    }

    func testReminders() {
        var a = rdv(d(2026, 11, 10, 10)); a.reminderMinutes = 15
        var b = rdv(d(2026, 11, 9, 10)); b.reminderMinutes = 0
        var c = rdv(d(2026, 11, 8, 10)); c.reminderMinutes = 10                  // déjà passé
        let none = rdv(d(2026, 11, 11, 10))                                     // sans rappel
        var honored = rdv(d(2026, 11, 12, 10)); honored.reminderMinutes = 5
        let arrival = Entry(title: "x", category: "Autre", kind: .actual, start: d(2026, 11, 12, 10), plannedID: honored.id)
        let up = Reminders.upcoming([a, b, c, none, honored, arrival], now: d(2026, 11, 8, 12))
        XCTAssertEqual(up.map(\.entry.id), [b.id, a.id])                         // triés ; passés, sans rappel, honorés exclus
        XCTAssertEqual(up[1].fire, d(2026, 11, 10, 9, 45))
        XCTAssertEqual(Reminders.upcoming([a, b], now: d(2026, 11, 1), limit: 1).count, 1)
    }

    func testStoreKeepsSeriesAndOldFilesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sillage-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (s, first) = Series.make(from: rdv(d(2026, 11, 2)), rule: Recurrence(frequency: .weekly, weekdays: [2]), calendar: fixed)
        let store = Store(url: url)
        try store.save([first], series: [s])
        let r = store.load()
        XCTAssertEqual(r.series, [s]); XCTAssertEqual(r.entries, [first])
        try store.save([first])                                                  // ancien appel, sans séries
        XCTAssertEqual(store.load().series, [])
    }

    // MARK: Grilles semaine et mois

    func testWeekStartsOnMonday() {
        let w = CalendarGrid.week(containing: d(2026, 11, 25), calendar: fixed)      // mercredi
        XCTAssertEqual(w.count, 7)
        XCTAssertEqual(w.first, d(2026, 11, 23, 0)); XCTAssertEqual(w.last, d(2026, 11, 29, 0))
    }

    func testMonthGridCoversWholeWeeks() {
        let g = CalendarGrid.month(containing: d(2026, 11, 10), calendar: fixed)     // nov. 2026 : 1er = dimanche
        XCTAssertEqual(g.count, 6)                                                   // il finit un lundi : 6 lignes
        XCTAssertEqual(g[0][0], d(2026, 10, 26, 0)); XCTAssertEqual(g[0][6], d(2026, 11, 1, 0))
        XCTAssertEqual(g[5][0], d(2026, 11, 30, 0)); XCTAssertEqual(g[5][6], d(2026, 12, 6, 0))
        XCTAssertTrue(g.allSatisfy { $0.count == 7 })
        // un mois de 28 jours commençant un lundi tient en 4 semaines (février 2027)
        XCTAssertEqual(CalendarGrid.month(containing: d(2027, 2, 14), calendar: fixed).count, 4)
        // mai 2026 : du vendredi 1er au dimanche 31, soit 5 semaines
        XCTAssertEqual(CalendarGrid.month(containing: d(2026, 5, 15), calendar: fixed).count, 5)
        XCTAssertTrue(CalendarGrid.isSameMonth(d(2026, 11, 1), d(2026, 11, 30), calendar: fixed))
        XCTAssertFalse(CalendarGrid.isSameMonth(d(2026, 10, 31), d(2026, 11, 1), calendar: fixed))
    }

    // MARK: Temps simultané

    func testSimultaneousTasksShareTheTime() {
        let now = at(18)
        // SFCO 9h–13h et Sillage 10h–14h : 3 h chacun en solo + 3 h partagées
        let list = [entry("SFCO", at(9), at(13), .actual, "Travail"), entry("Sillage", at(10), at(14), .actual, "Loisirs")]
        let t = DayLogic.totals(list, on: day, now: now, calendar: cal)
        let dict = Dictionary(uniqueKeysWithValues: t.map { ($0.category, $0.duration) })
        let soloPlusHalfOfShared: TimeInterval = 3600 + 5400                 // 1 h seul + la moitié des 3 h communes
        XCTAssertEqual(dict["Travail"], soloPlusHalfOfShared)
        XCTAssertEqual(dict["Loisirs"], soloPlusHalfOfShared)
        let total = t.reduce(0.0) { $0 + $1.duration }
        XCTAssertEqual(total, 18000)                                          // 5 h : le temps réellement écoulé (9 h → 14 h)
        let cumulative = DayLogic.totals(list, on: day, now: now, shared: false, calendar: cal)
        XCTAssertEqual(cumulative.reduce(0.0) { $0 + $1.duration }, 28800)   // ancien comptage : 4 h + 4 h
    }

    func testSharingWithRunningTaskAndSameCategory() {
        let now = at(12)
        let list = [entry("a", at(8), nil, .actual, "Travail"), entry("b", at(9), nil, .actual, "Travail"),
                    entry("c", at(9), at(10), .planned, "Santé")]                // le prévu ne compte pas
        let t = DayLogic.totals(list, on: day, now: now, calendar: cal)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].duration, 4 * 3600)                                // 8 h → 12 h, une seule fois
    }

    func testNoOverlapIsUnchanged() {
        let now = at(18)
        let list = [entry("a", at(8), at(9), .actual, "Repas"), entry("b", at(9), at(11), .actual, "Travail")]
        let t = DayLogic.totals(list, on: day, now: now, calendar: cal)
        XCTAssertEqual(t.map(\.category), ["Travail", "Repas"])
        XCTAssertEqual(t.map(\.duration), [7200, 3600])
    }

    func testHasSimultaneous() {
        let now = at(18)
        let parallel = [entry("a", at(9), at(11), .actual), entry("b", at(10), at(12), .actual)]
        XCTAssertTrue(DayLogic.hasSimultaneous(parallel, on: day, now: now, calendar: cal))
        let sequential = [entry("a", at(9), at(10), .actual), entry("b", at(10), at(12), .actual)]
        XCTAssertFalse(DayLogic.hasSimultaneous(sequential, on: day, now: now, calendar: cal))
        let plannedOnly = [entry("a", at(9), at(11), .planned), entry("b", at(10), at(12), .actual)]
        XCTAssertFalse(DayLogic.hasSimultaneous(plannedOnly, on: day, now: now, calendar: cal))   // prévu et réel ne comptent pas
    }

    // MARK: Bilan par tâche, récents, annuler

    func testTaskTotalsGroupByTitleCaseAndSpaces() {
        let now = at(18)
        let list = [
            entry("SFCO", at(9), at(11), .actual, "Travail"),
            entry("sfco ", at(11), at(12), .actual, "Travail"),           // même tâche : casse et espace ignorés
            entry("Sillage", at(10), at(12), .actual, "Loisirs"),
        ]
        let t = DayLogic.taskTotals(list, on: day, now: now, calendar: cal)
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].title, "SFCO")                                  // la graphie la plus utilisée (2 h contre 1 h)
        XCTAssertEqual(t[0].duration, 7200)                                  // 9–10 seul (1 h) + 10–12 partagé avec Sillage (2 × 30 min)
        XCTAssertEqual(t[1].duration, 3600)                                  // 10–12 : la moitié de 2 h
        XCTAssertEqual(t.reduce(0.0) { $0 + $1.duration }, 10800)           // 3 h : le temps écoulé de 9 h à 12 h
    }

    func testTaskTotalsExactNumbers() {
        let now = at(18)
        let list = [entry("SFCO", at(9), at(12), .actual, "Travail"), entry("Sillage", at(10), at(12), .actual, "Loisirs")]
        let t = DayLogic.taskTotals(list, on: day, now: now, calendar: cal)
        XCTAssertEqual(t[0].title, "SFCO"); XCTAssertEqual(t[0].duration, 3600 + 3600)      // 1 h seul + moitié de 2 h
        XCTAssertEqual(t[1].title, "Sillage"); XCTAssertEqual(t[1].duration, 3600)          // moitié de 2 h
        XCTAssertEqual(t[0].category, "Travail")
    }

    func testRecentsAreDistinctAndSkipPresetsAndRunning() {
        let now = at(20)
        let list = [
            entry("SFCO", at(8), at(9), .actual, "Travail"),
            entry("Douche", at(9), at(10), .actual, "Hygiène"),             // déjà un raccourci
            entry("Sillage", at(10), at(11), .actual, "Loisirs"),
            entry("sfco", at(12), at(13), .actual, "Travail"),              // doublon de SFCO, plus récent
            entry("Facture", at(14), nil, .actual, "Travail"),              // en cours : exclue
            entry("Médecin", at(15), at(16), .planned, "Santé"),            // prévu : exclu
        ]
        let r = Recents.recent(list, now: now)
        XCTAssertEqual(r.map(\.title), ["sfco", "Sillage"])                 // la plus récente d'abord, sans doublon
        XCTAssertEqual(Recents.recent(list, limit: 1, now: now).count, 1)
    }

    func testUndoStack() {
        var stack = UndoStack<Int>(limit: 3)
        XCTAssertFalse(stack.canUndo)
        var state = 0
        for next in 1...4 { stack.record(state); state = next }            // 0→1→2→3→4 ; limite 3 : 0 oublié
        XCTAssertEqual(stack.undo(current: state), 3); state = 3
        XCTAssertEqual(stack.undo(current: state), 2); state = 2
        XCTAssertTrue(stack.canRedo)
        XCTAssertEqual(stack.redo(current: state), 3); state = 3
        stack.record(state); state = 9                                      // nouvelle modification : le « rétablir » disparaît
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.undo(current: state), 3)
        XCTAssertEqual(stack.undo(current: 3), 2)
        XCTAssertEqual(stack.undo(current: 2), 1)
        XCTAssertNil(stack.undo(current: 1))                                // 0 a été oublié (limite 3)
    }

    // MARK: Rapports par période

    func testReportDaysForPeriods() {
        let anchor = d(2026, 11, 25)
        let now = d(2026, 11, 25, 18)
        XCTAssertEqual(Reports.days(for: .day, anchor: anchor, entries: [], now: now, calendar: fixed), [d(2026, 11, 25, 0)])
        XCTAssertEqual(Reports.days(for: .week, anchor: anchor, entries: [], now: now, calendar: fixed).count, 7)
        let month = Reports.days(for: .month, anchor: anchor, entries: [], now: now, calendar: fixed)
        XCTAssertEqual(month.count, 30); XCTAssertEqual(month.first, d(2026, 11, 1, 0)); XCTAssertEqual(month.last, d(2026, 11, 30, 0))
        // tout : de la première entrée réelle à aujourd'hui
        let old = Entry(title: "x", category: "Autre", kind: .actual, start: d(2026, 11, 20, 8), end: d(2026, 11, 20, 9))
        let all = Reports.days(for: .all, anchor: anchor, entries: [old], now: now, calendar: fixed)
        XCTAssertEqual(all.count, 6); XCTAssertEqual(all.first, d(2026, 11, 20, 0)); XCTAssertEqual(all.last, d(2026, 11, 25, 0))
        XCTAssertEqual(Reports.days(for: .all, anchor: anchor, entries: [], now: now, calendar: fixed).count, 1)   // rien : aujourd'hui
    }

    func testTaskSummaryAcrossDays() {
        let now = d(2026, 11, 26, 18)
        func e(_ title: String, _ day: Int, _ h1: Int, _ h2: Int, _ cat: String = "Travail") -> Entry {
            Entry(title: title, category: cat, kind: .actual, start: d(2026, 11, day, h1), end: d(2026, 11, day, h2))
        }
        let list = [e("SFCO", 24, 9, 12), e("sfco", 25, 14, 16), e("SFCO", 25, 16, 17), e("Sillage", 25, 14, 16, "Loisirs"),
                    Entry(title: "SFCO", category: "Travail", kind: .planned, start: d(2026, 11, 26, 9), end: d(2026, 11, 26, 10))]
        let days = Reports.days(for: .all, anchor: now, entries: list, now: now, calendar: fixed)
        let s = Reports.summaries(list, days: days, now: now, calendar: fixed)
        XCTAssertEqual(s.map(\.key), ["sfco", "sillage"])
        let sfco = s[0]
        let h: TimeInterval = 3600
        let day24: TimeInterval = 3 * h                                       // 9 h–12 h, seul
        let day25: TimeInterval = 2 * h                                       // 14–16 partagé avec Sillage (1 h) + 16–17 (1 h)
        XCTAssertEqual(sfco.total, day24 + day25)
        XCTAssertEqual(sfco.sessions, 3); XCTAssertEqual(sfco.activeDays, 2)
        XCTAssertEqual(sfco.perDay.map(\.duration), [day24, day25])
        XCTAssertEqual(sfco.averagePerActiveDay, 2.5 * h)
        XCTAssertEqual(sfco.first, d(2026, 11, 24, 9)); XCTAssertEqual(sfco.last, d(2026, 11, 25, 17))
        XCTAssertEqual(s[1].total, h)                                         // moitié de 14–16
        // la période limite le calcul : seulement le 25
        let only25 = Reports.summaries(list, days: [d(2026, 11, 25, 0)], now: now, calendar: fixed)
        XCTAssertEqual(only25.first { $0.key == "sfco" }?.total, day25)
        XCTAssertEqual(Reports.sessions(of: "sfco", in: list, days: days, calendar: fixed).count, 3)
        XCTAssertEqual(Reports.sessions(of: "sfco", in: list, days: [d(2026, 11, 25, 0)], calendar: fixed).first?.start, d(2026, 11, 25, 16))
    }

    func testRecentsUseTheMostUsedSpelling() {
        let now = at(20)
        let list = [entry("SFCO", at(8), at(9), .actual), entry("SFCO", at(9), at(10), .actual), entry("sfco", at(11), at(12), .actual)]
        XCTAssertEqual(Recents.recent(list, now: now).map(\.title), ["SFCO"])     // 2 contre 1, même si la dernière était en minuscules
    }

    // MARK: Récap du jour

    func testRecapSegmentsMergeGapsAndSimultaneous() {
        let now = at(20)
        let list = [
            entry("Douche", at(7, 10), at(7, 40), .actual, "Hygiène"),
            entry("Petit-déjeuner", at(7, 40), at(8, 10), .actual, "Repas"),
            entry("SFCO", at(9), at(12), .actual, "Travail"),
            entry("Sillage", at(10), at(11), .actual, "Loisirs"),          // en parallèle de SFCO
            entry("Sieste", at(12, 3), at(12, 5), .actual, "Sommeil"),     // trou de 3 min avant : ignoré
        ]
        let r = Recap.build(list, on: day, now: now, calendar: cal)
        // Douche | Petit-déj | trou 8h10–9h | SFCO | SFCO + Sillage | SFCO | trou 12h–12h03 ignoré | Sieste
        XCTAssertEqual(r.segments.map { $0.isGap ? "—" : $0.title },
                       ["Douche", "Petit-déjeuner", "—", "SFCO", "SFCO + Sillage", "SFCO", "Sieste"])
        let gap = r.segments[2]
        XCTAssertEqual(gap.start, at(8, 10)); XCTAssertEqual(gap.end, at(9)); XCTAssertEqual(gap.duration, 50 * 60)
        XCTAssertTrue(r.hasSimultaneous)
        XCTAssertEqual(r.firstStart, at(7, 10)); XCTAssertEqual(r.lastEnd, at(12, 5)); XCTAssertFalse(r.isStillRunning)
        let h: TimeInterval = 3600
        XCTAssertEqual(r.tracked, (30 + 30) * 60 + 3 * h + 2 * 60)            // 7h10–8h10, 9h–12h, 12h03–12h05 : le temps écoulé, une seule fois
    }

    func testRecapRunningTaskAndEmptyDay() {
        let now = at(15)
        let r = Recap.build([entry("Sillage", at(14), nil, .actual, "Loisirs")], on: day, now: now, calendar: cal)
        XCTAssertTrue(r.isStillRunning); XCTAssertTrue(r.segments[0].isLive); XCTAssertEqual(r.tracked, 3600)
        let empty = Recap.build([], on: day, now: now, calendar: cal)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(Recap.markdown(empty, now: now).contains("Rien d'enregistré"))
    }

    func testRecapAppointmentStatuses() {
        let now = at(15)
        func plan(_ t: String, _ h1: Int, _ h2: Int) -> Entry { entry(t, at(h1), at(h2), .planned, "Santé") }
        let honored = plan("Médecin", 9, 10), covered = plan("Dentiste", 11, 12), missed = plan("Banque", 13, 14)
        let ongoing = plan("Réunion", 14, 16), upcoming = plan("Dîner", 19, 20)
        let arrival = Entry(title: "Médecin", category: "Santé", kind: .actual, start: at(9, 10), end: at(10), plannedID: honored.id)
        let list = [honored, covered, missed, ongoing, upcoming, arrival,
                    entry("Chez le dentiste", at(11), at(11, 40), .actual, "Santé")]    // 40 min sur 60 : couvert
        let r = Recap.build(list, on: day, now: now, calendar: cal)
        let status = Dictionary(uniqueKeysWithValues: r.appointments.map { ($0.entry.title, $0.status) })
        XCTAssertEqual(status["Médecin"], .honored("10 min de retard"))
        XCTAssertEqual(status["Dentiste"], .covered)
        XCTAssertEqual(status["Banque"], .missed)
        XCTAssertEqual(status["Réunion"], .ongoing)
        XCTAssertEqual(status["Dîner"], .upcoming)
        XCTAssertEqual(r.appointments.map(\.entry.title), ["Médecin", "Dentiste", "Banque", "Réunion", "Dîner"])   // ordre chronologique
    }

    func testRecapMarkdown() {
        let now = at(20)
        let list = [entry("SFCO", at(9), at(10), .actual, "Travail"), entry("Réunion", at(9), at(9, 30), .planned, "Travail")]
        let text = Recap.markdown(Recap.build(list, on: day, now: now, calendar: cal), now: now)
        XCTAssertTrue(text.hasPrefix("# "))
        XCTAssertTrue(text.contains("## Journée")); XCTAssertTrue(text.contains("SFCO")); XCTAssertTrue(text.contains("1 h 00"))
        XCTAssertTrue(text.contains("## Temps par tâche")); XCTAssertTrue(text.contains("## Rendez-vous"))
    }

    func testOnlyTheSegmentTouchingNowIsLive() {
        let now = at(18)
        let list = [entry("SFCO", at(14), at(15), .actual, "Travail"), entry("Sillage", at(14), nil, .actual, "Loisirs")]
        let r = Recap.build(list, on: day, now: now, calendar: cal)
        XCTAssertEqual(r.segments.map(\.title), ["SFCO + Sillage", "Sillage"])
        XCTAssertEqual(r.segments.map(\.isLive), [false, true])         // 14–15 est terminé ; 15–18 continue
        XCTAssertTrue(r.segments[0].isRunning)                           // mais Sillage y tournait bel et bien
    }

    // MARK: Sauvegardes et export

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sillage-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRollingSnapshotsAreThrottledDedupedAndPruned() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(url: dir.appendingPathComponent("data.json"))
        XCTAssertNil(store.snapshotIfNeeded(now: at(9)))                         // pas de fichier : rien à copier
        try store.save([entry("a", at(9), at(10))])
        let first = store.snapshotIfNeeded(now: at(9))
        XCTAssertNotNil(first)
        XCTAssertNil(store.snapshotIfNeeded(now: at(9, 5)))                      // même contenu : pas de doublon
        try store.save([entry("a", at(9), at(10)), entry("b", at(10), at(11))])
        XCTAssertNil(store.snapshotIfNeeded(now: at(9, 5)))                      // modifié, mais moins de 10 min après
        XCTAssertNotNil(store.snapshotIfNeeded(now: at(9, 12)))                  // 10 min passées
        XCTAssertEqual(store.latestSnapshotDate(), at(9, 12))
        // « force » (fermeture de l'app) ignore le délai
        try store.save([entry("c", at(11), at(12))])
        XCTAssertNotNil(store.snapshotIfNeeded(now: at(9, 13), force: true))
        // élagage : on ne garde que les `keep` dernières
        for i in 0..<5 {
            try store.save([entry("n\(i)", at(12 + i), at(13 + i))])
            _ = store.snapshotIfNeeded(now: at(10 + i), minInterval: 0, keep: 3, force: true)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.snapshotsDirectory.path).count, 3)
    }

    func testSnapshotsNeverCopyUnreadableOrEmptyData() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(url: dir.appendingPathComponent("data.json"))
        try store.save([entry("a", at(9), at(10))])
        XCTAssertNotNil(store.snapshotIfNeeded(now: at(9)))
        try Data("{ cassé".utf8).write(to: store.url)
        XCTAssertNil(store.snapshotIfNeeded(now: at(12), force: true))           // illisible : jamais copié
        try store.save([])
        XCTAssertNil(store.snapshotIfNeeded(now: at(13), force: true))           // vide : n'écrase pas la mémoire des bonnes copies
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.snapshotsDirectory.path).count, 1)
    }

    func testMirrorToUserFolder() throws {
        let dir = tempDir(), mirror = tempDir()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: mirror) }
        let store = Store(url: dir.appendingPathComponent("data.json"))
        try store.save([entry("a", at(9), at(10))])
        let copy = try XCTUnwrap(store.mirror(to: mirror, now: at(9)))
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("Sillage-sauvegarde-"))
        XCTAssertEqual(Store.readBackup(at: copy)?.entries.count, 1)
        // dossier absent (disque débranché) : rien n'est créé
        let missing = dir.appendingPathComponent("disque-debranche")
        XCTAssertNil(store.mirror(to: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        // un fichier par jour, 30 jours gardés
        for d in 1...35 { _ = store.mirror(to: mirror, now: at(9).addingTimeInterval(Double(d) * 86400)) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: mirror.path).count, 30)
    }

    func testExportAndReadBackup() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (s, first) = Series.make(from: rdv(d(2026, 11, 2)), rule: Recurrence(frequency: .weekly), calendar: fixed)
        let file = dir.appendingPathComponent("export.json")
        try Store.export(entries: [first, entry("a", at(9), at(10))], series: [s], to: file)
        let back = try XCTUnwrap(Store.readBackup(at: file))
        XCTAssertEqual(back.entries.count, 2); XCTAssertEqual(back.series, [s])
        // un fichier quelconque n'est pas une sauvegarde
        let other = dir.appendingPathComponent("autre.json")
        try Data(#"{"foo": 1}"#.utf8).write(to: other)
        XCTAssertNil(Store.readBackup(at: other))
        XCTAssertNil(Store.readBackup(at: dir.appendingPathComponent("inexistant.json")))
    }

    func testCSVExport() {
        let now = at(18)
        let list = [
            entry("Réunion; \"client\"", at(10), at(11, 30), .actual, "Travail"),
            Entry(title: "Médecin", category: "Santé", kind: .planned, start: at(9), end: at(10)),
            entry("Sillage", at(14), nil, .actual, "Loisirs"),
        ]
        let csv = CSVExport.csv(list, now: now, calendar: cal)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Type;Titre;Catégorie;Début;Fin;Durée (min);Durée (h:mm);En cours;Notes\r\n"))
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[1].hasPrefix("Prévu;Médecin;Santé;2026-11-25 09:00;2026-11-25 10:00;60;1:00;non;"))   // triées par début
        XCTAssertTrue(lines[2].contains("\"Réunion; \"\"client\"\"\""))                                       // échappement
        XCTAssertTrue(lines[2].hasSuffix("90;1:30;non;"))
        XCTAssertTrue(lines[3].hasSuffix(";240;4:00;oui;"))                                                      // en cours : jusqu'à maintenant
        // une période : seulement ce qui la touche
        let onlyMorning = CSVExport.csv(list, now: now, from: at(0), to: at(10), calendar: cal)
        XCTAssertEqual(onlyMorning.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 2)           // en-tête + Médecin
    }

    func testKeepCopyBeforeRestore() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(url: dir.appendingPathComponent("data.json"))
        XCTAssertNil(store.keepCopyBeforeRestore(now: at(9)))                    // rien à garder
        try Data("{ même illisible".utf8).write(to: store.url)
        let copy = try XCTUnwrap(store.keepCopyBeforeRestore(now: at(9)))
        XCTAssertEqual(try String(contentsOf: copy), "{ même illisible")
    }

    // MARK: Calendriers externes

    func testCalendarImportFiltersAndMaps() {
        func ev(_ id: String, _ cal: String, _ h1: Int, _ h2: Int, allDay: Bool = false, declined: Bool = false,
                cancelled: Bool = false, title: String = "Réunion") -> ExternalEvent {
            ExternalEvent(identifier: id, calendarID: cal, calendarTitle: "Cal \(cal)", title: title, start: at(h1), end: at(h2),
                          isAllDay: allDay, isDeclined: declined, isCancelled: cancelled)
        }
        let events = [ev("a", "perso", 14, 15), ev("b", "pro", 9, 10), ev("c", "perso", 0, 24, allDay: true),
                      ev("d", "pro", 11, 12, declined: true), ev("e", "pro", 12, 13, cancelled: true),
                      ev("f", "pro", 16, 16, title: "  "), ev("g", "perso", 17, 18)]
        let all = CalendarImport.entries(from: events)
        XCTAssertEqual(all.map(\.start), [at(9), at(14), at(16), at(17)])          // triés ; refusé, annulé, journée entière écartés
        XCTAssertTrue(all.allSatisfy { $0.kind == .planned && $0.category == "Calendrier" && $0.isExternal })
        XCTAssertEqual(all[0].source, "Cal pro")
        XCTAssertEqual(all[2].title, "Sans titre"); XCTAssertEqual(all[2].end, at(16, 30))   // fin invalide : 30 min
        XCTAssertEqual(CalendarImport.entries(from: events, showAllDay: true).count, 5)
        XCTAssertEqual(CalendarImport.entries(from: events, selectedCalendars: ["perso"]).map(\.start), [at(14), at(17)])
        XCTAssertEqual(CalendarImport.entries(from: events, selectedCalendars: []).count, 0)
    }

    func testStableIDsDistinguishOccurrences() {
        let id1 = CalendarImport.stableID(identifier: "evt", start: at(9))
        XCTAssertEqual(id1, CalendarImport.stableID(identifier: "evt", start: at(9)))             // stable d'un lancement à l'autre
        XCTAssertNotEqual(id1, CalendarImport.stableID(identifier: "evt", start: at(9).addingTimeInterval(86400)))  // autre occurrence
        XCTAssertNotEqual(id1, CalendarImport.stableID(identifier: "autre", start: at(9)))
    }

    func testArrivingAtAnExternalAppointmentLinksByStableID() {
        let now = at(10)
        let planned = CalendarImport.entries(from: [ExternalEvent(identifier: "x", calendarID: "c", calendarTitle: "Perso",
                                                                  title: "Dentiste", start: at(9), end: at(10))])[0]
        // « J'y suis » : une activité réelle liée par l'identifiant stable (le rendez-vous n'est pas dans les données enregistrées)
        let saved = Actions.startTask([], title: planned.title, category: "Autre", plannedID: planned.id, now: at(9, 10), stopRunning: true)
        let shown = saved + [planned]
        XCTAssertTrue(Actions.isArrived(planned, in: saved))
        XCTAssertEqual(Actions.punctuality(of: saved[0], in: shown), "10 min de retard")
        let recap = Recap.build(shown, on: day, now: now, calendar: cal)
        XCTAssertEqual(recap.appointments.first?.status, .honored("10 min de retard"))
        // si le calendrier est désactivé plus tard, le lien reste sans effet mais ne casse rien
        XCTAssertNil(Actions.punctuality(of: saved[0], in: saved))
    }

    // MARK: Renommer / fusionner, séries, notes, objectifs

    func testRenameAndMergeTasks() {
        let list = [entry("Sfco", at(9), at(10), .actual, "Travail"), entry("SFCO", at(11), at(12), .actual, "Travail"),
                    entry("Facture", at(13), at(14), .actual, "Autre"),
                    Entry(title: "Sfco", category: "Travail", kind: .planned, start: at(15), end: at(16))]     // un rendez-vous prévu ne change pas
        XCTAssertEqual(Actions.sessionCount(list, key: "sfco"), 2)
        let renamed = Actions.renameTask(list, key: "sfco", to: "  SFCO  ")
        XCTAssertEqual(renamed.changed, 1)                                       // « SFCO » était déjà bon
        XCTAssertEqual(renamed.entries.filter { $0.kind == .actual }.map(\.title), ["SFCO", "SFCO", "Facture"])
        XCTAssertEqual(renamed.entries[3].title, "Sfco")
        // fusion : « Facture » dans « SFCO », avec la catégorie de la cible
        let merged = Actions.renameTask(renamed.entries, key: "facture", to: "SFCO", category: "Travail")
        XCTAssertEqual(merged.changed, 1)
        XCTAssertEqual(Actions.sessionCount(merged.entries, key: "sfco"), 3)
        XCTAssertEqual(merged.entries[2].category, "Travail")
        XCTAssertEqual(Actions.renameTask(list, key: "sfco", to: "   ").changed, 0)             // un nom vide est refusé
    }

    func testApplyToFollowingChangesOnlyLaterUnlivedOccurrences() {
        let now = d(2026, 11, 2, 8)
        var first = rdv(d(2026, 11, 2, 10)); first.title = "Kiné"
        let (s0, f0) = Series.make(from: first, rule: Recurrence(frequency: .daily), calendar: fixed)
        var series = [s0]; var entries = [f0]
        Series.topUp(&series, entries: &entries, now: now, horizonDays: 6, calendar: fixed)   // 2 → 8 novembre
        entries = Actions.arrive(entries, at: entries.first { $0.start == d(2026, 11, 6, 10) }!.id, now: d(2026, 11, 6, 10, 5), stopRunning: false)
        let original = entries.first { $0.start == d(2026, 11, 4, 10) }!
        var edited = original
        edited.title = "Kiné du dos"; edited.start = d(2026, 11, 4, 11, 30); edited.end = d(2026, 11, 4, 12, 15); edited.notes = "Apporter la carte"
        Series.applyToFollowing(original: original, edited: edited, series: &series, entries: &entries, calendar: fixed)
        let planned = entries.filter { $0.kind == .planned }.sorted { $0.start < $1.start }
        XCTAssertEqual(planned.map(\.title), ["Kiné", "Kiné", "Kiné du dos", "Kiné du dos", "Kiné", "Kiné du dos", "Kiné du dos"])   // le 6 était vécu : intact
        XCTAssertEqual(planned.map { fixed.component(.hour, from: $0.start) }, [10, 10, 11, 11, 10, 11, 11])
        XCTAssertEqual(planned[5].end, d(2026, 11, 7, 12, 15))                  // durée de 45 min reportée
        XCTAssertEqual(planned[2].notes, "Apporter la carte")
        XCTAssertEqual(series[0].template.title, "Kiné du dos")
        // les occurrences générées plus tard suivent le nouveau modèle
        Series.topUp(&series, entries: &entries, now: d(2026, 11, 8, 8), horizonDays: 6, calendar: fixed)
        let later = entries.first { $0.start == d(2026, 11, 12, 11, 30) }
        XCTAssertEqual(later?.title, "Kiné du dos")
        XCTAssertNotNil(later?.end)
    }

    func testApplyToFollowingCanMoveOnlyTheEditedDate() {
        let now = d(2026, 11, 2, 8)
        let (s0, f0) = Series.make(from: rdv(d(2026, 11, 2, 10)), rule: Recurrence(frequency: .daily), calendar: fixed)
        var series = [s0]; var entries = [f0]
        Series.topUp(&series, entries: &entries, now: now, horizonDays: 3, calendar: fixed)
        let original = entries.first { $0.start == d(2026, 11, 3, 10) }!
        var edited = original; edited.start = d(2026, 11, 3, 15); edited.end = d(2026, 11, 3, 16)
        Series.applyToFollowing(original: original, edited: edited, series: &series, entries: &entries, calendar: fixed)
        XCTAssertEqual(entries.filter { $0.id == original.id }.first?.start, d(2026, 11, 3, 15))
        XCTAssertEqual(entries.first { fixed.component(.day, from: $0.start) == 4 }?.start, d(2026, 11, 4, 15))   // même jour, nouvelle heure
        XCTAssertEqual(entries.first { fixed.component(.day, from: $0.start) == 2 }?.start, d(2026, 11, 2, 10))   // avant : intact
    }

    func testNotesFlowIntoRecapAndCSV() {
        let now = at(20)
        var a = entry("SFCO", at(9), at(10), .actual, "Travail"); a.notes = "  Corrigé le bug du panier  "
        let r = Recap.build([a], on: day, now: now, calendar: cal)
        XCTAssertEqual(r.segments[0].notes, ["Corrigé le bug du panier"])
        XCTAssertTrue(Recap.markdown(r, now: now).contains("  - _Corrigé le bug du panier_"))
        XCTAssertTrue(CSVExport.csv([a], now: now, calendar: cal).contains("Corrigé le bug du panier"))
        XCTAssertNil(entry("x", at(9), at(10)).trimmedNotes)
    }

    func testGoalProgressForTasksCategoriesAndStates() {
        let now = d(2026, 11, 25, 12)                                            // mercredi ; semaine du 23 au 29
        func e(_ t: String, _ day: Int, _ h1: Int, _ h2: Int, _ cat: String = "Travail") -> Entry {
            Entry(title: t, category: cat, kind: .actual, start: d(2026, 11, day, h1), end: d(2026, 11, day, h2))
        }
        let list = [e("SFCO", 23, 9, 13), e("sfco", 24, 9, 12), e("SFCO", 25, 9, 11), e("Sillage", 24, 9, 12, "Loisirs"), e("SFCO", 16, 9, 17)]
        let weekly = Goal(taskKey: "sfco", title: "SFCO", hours: 20, period: .week)
        let p = Goals.progress(weekly, entries: list, anchor: now, now: now, calendar: fixed)
        // SFCO : lundi 4 h + mardi 3 h (3 h partagées avec Sillage → 1 h 30) + mercredi 2 h ; la semaine précédente est ignorée
        let hour: TimeInterval = 3600
        let monday: TimeInterval = 4 * hour, tuesday: TimeInterval = 1.5 * hour, wednesday: TimeInterval = 2 * hour
        let doneExpected: TimeInterval = monday + tuesday + wednesday
        XCTAssertEqual(p.done, doneExpected)
        XCTAssertEqual(p.state, .inProgress)
        XCTAssertEqual(p.daysLeft, 5)                                            // mercredi → dimanche
        let missing: TimeInterval = 20 * hour - doneExpected
        XCTAssertEqual(try XCTUnwrap(p.perRemainingDay), missing / 5, accuracy: 0.1)
        XCTAssertEqual(Goals.progress(Goal(taskKey: "sfco", title: "SFCO", hours: 7, period: .week), entries: list, anchor: now, now: now, calendar: fixed).state, .reached)
        // « au plus » : dépassé
        XCTAssertEqual(Goals.progress(Goal(category: "Loisirs", title: "Loisirs", hours: 1, period: .week, kind: .atMost),
                                      entries: list, anchor: now, now: now, calendar: fixed).state, .exceeded)
        // objectif du jour
        let daily = Goals.progress(Goal(taskKey: "sfco", title: "SFCO", hours: 3, period: .day), entries: list, anchor: now, now: now, calendar: fixed)
        XCTAssertEqual(daily.done, wednesday); XCTAssertNil(daily.perRemainingDay)
    }

    func testStoreKeepsGoalsAndOldFilesStillLoad() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(url: dir.appendingPathComponent("data.json"))
        let goal = Goal(taskKey: "sfco", title: "SFCO", hours: 20, period: .week)
        try store.save([entry("a", at(9), at(10))], series: [], goals: [goal])
        XCTAssertEqual(store.load().goals, [goal])
        let backup = dir.appendingPathComponent("sauvegarde.json")
        try Store.export(entries: [entry("a", at(9), at(10))], series: [], goals: [goal], to: backup)
        XCTAssertEqual(Store.readBackup(at: backup)?.goals, [goal])
        // un ancien fichier (sans objectifs ni notes) se lit toujours
        let old = dir.appendingPathComponent("ancien.json")
        try Data(#"{"entries":[{"id":"6F0B9C1E-0000-4000-8000-000000000001","title":"a","category":"Autre","kind":"actual","start":"2026-11-25T08:00:00Z"}]}"#.utf8).write(to: old)
        let r = Store.readBackup(at: old)
        XCTAssertEqual(r?.entries.count, 1); XCTAssertEqual(r?.goals, []); XCTAssertNil(r?.entries[0].notes)
        // des objectifs seuls suffisent à rendre le fichier « non vide » pour les copies de secours
        try store.save([], series: [], goals: [goal])
        XCTAssertNotNil(store.snapshotIfNeeded(now: at(9), force: true))
    }
}
