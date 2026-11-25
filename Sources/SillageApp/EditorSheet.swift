import SwiftUI
import SillageCore

struct EditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: AppModel.EditorTarget
    @State private var entry: Entry
    @State private var hasEnd: Bool
    @State private var end: Date

    init(target: AppModel.EditorTarget) {
        self.target = target
        _entry = State(initialValue: target.entry)
        _hasEnd = State(initialValue: target.entry.end != nil)
        _end = State(initialValue: target.entry.end ?? Date())
    }

    private var planned: Bool { entry.kind == .planned }
    private var valid: Bool {
        !entry.title.trimmingCharacters(in: .whitespaces).isEmpty && (!hasEnd || end > entry.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.isNew ? (planned ? "Nouveau rendez-vous" : "Activité passée")
                              : (planned ? "Rendez-vous" : "Activité")).font(.title3.weight(.semibold))
            Form {
                TextField("Titre", text: $entry.title)
                Picker("Catégorie", selection: $entry.category) {
                    ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("Début", selection: $entry.start)
                if planned {
                    DatePicker("Fin", selection: $end)
                } else {
                    Toggle("Terminée", isOn: $hasEnd)
                    if hasEnd { DatePicker("Fin", selection: $end) }
                }
            }
            if hasEnd && end <= entry.start {
                Text("La fin doit être après le début.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                if !target.isNew {
                    Button("Supprimer", role: .destructive) { model.delete(entry.id); dismiss() }
                }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    var e = entry
                    e.title = e.title.trimmingCharacters(in: .whitespaces)
                    e.end = (planned || hasEnd) ? end : nil
                    model.save(e)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
