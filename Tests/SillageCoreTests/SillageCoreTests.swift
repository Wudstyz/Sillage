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
        XCTAssertEqual(store.load(), [])
        let e = Entry(title: "Médecin", category: "Santé", kind: .planned, start: at(10), end: at(11))
        try store.save([e])
        XCTAssertEqual(store.load(), [e])
    }
}
