import Foundation
import SwiftUI
import SillageCore

@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var day = Date()
    @Published var now = Date()
    /// Entrée en cours d'édition dans la feuille modale (nouvelle ou existante).
    @Published var editor: EditorTarget?
    @Published var saveError: String?

    private let store: Store
    private var timer: Timer?

    init(store: Store = .default) {
        self.store = store
        entries = store.load()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
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
    func start(title: String, category: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        now = Date()
        entries.append(Entry(title: t, category: category, kind: .actual, start: now))
        persist()
    }

    func stop(_ id: UUID) {
        now = Date()
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].end = max(now, entries[i].start)
        persist()
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

    func save(_ entry: Entry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry } else { entries.append(entry) }
        persist()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do { try store.save(entries) } catch { saveError = error.localizedDescription }
    }
}
