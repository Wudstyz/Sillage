import SwiftUI
import SillageCore

/// Renommer une tâche partout, ou la fusionner avec une autre (même nom = même tâche).
struct RenameTaskSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let task: TaskSummary
    @State private var name: String
    @State private var category: String

    init(task: TaskSummary) {
        self.task = task
        _name = State(initialValue: task.title)
        _category = State(initialValue: task.category)
    }

    private var others: [TaskSummary] {
        Reports.summaries(model.entries, days: Reports.days(for: .all, anchor: model.now, entries: model.entries, now: model.now),
                          now: model.now).filter { $0.key != task.key }
    }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// La tâche existante qui porterait ce nom (fusion), s'il y en a une.
    private var mergeTarget: TaskSummary? { others.first { $0.key == DayLogic.taskKey(trimmed) } }
    private var sessions: Int { Actions.sessionCount(model.entries, key: task.key) }
    private var unchanged: Bool { trimmed == task.title && category == task.category }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.merge").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Renommer ou fusionner").font(Theme.rounded(20, .bold)).foregroundStyle(Theme.ink)
            }
            Text("Toutes les séances de « \(task.title) » (\(sessions)) prennent le nouveau nom. Si ce nom est celui d'une autre tâche, elles fusionnent avec elle. Les rendez-vous prévus ne changent pas.")
                .font(Theme.rounded(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)

            TextField("Nouveau nom", text: $name).textFieldStyle(.roundedBorder)

            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fusionner avec").sectionLabel()
                    HStack(spacing: 6) {
                        ForEach(Array(others.prefix(6))) { o in
                            Button(o.title) { name = o.title; category = o.category }
                                .buttonStyle(ChipButtonStyle(category: o.category)).lineLimit(1)
                        }
                    }
                }
            }

            Picker("Catégorie des séances", selection: $category) {
                ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
            }

            if let target = mergeTarget {
                Label("Fusion avec « \(target.title) » : les \(sessions) séances rejoignent ses \(Actions.sessionCount(model.entries, key: target.key)) séances.",
                      systemImage: "arrow.triangle.merge")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
            }
            if category != task.category {
                Label("Les \(sessions) séances passent dans la catégorie « \(category) » : les bilans par catégorie des jours passés changent.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.rounded(12)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
            }
            Text("Vous pouvez annuler avec ⌘Z.").font(Theme.rounded(12)).foregroundStyle(Theme.muted)

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(mergeTarget == nil ? "Renommer" : "Fusionner") {
                    model.renameTask(key: task.key, to: trimmed, category: category == task.category ? nil : category)
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty || unchanged)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.background)
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }
}
