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
}
