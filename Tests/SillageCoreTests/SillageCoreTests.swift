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
}
