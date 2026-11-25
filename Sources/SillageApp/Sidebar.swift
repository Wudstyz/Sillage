import SwiftUI
import SillageCore

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @State private var title = ""
    @State private var category = "Travail"

    var body: some View {
        List {
            Section("Je commence") {
                TextField("Que faites-vous ?", text: $title)
                    .onSubmit(begin)
                Picker("Catégorie", selection: $category) {
                    ForEach(Categories.all, id: \.self) { c in
                        Label(c, systemImage: "circle.fill").foregroundStyle(Theme.color(for: c)).tag(c)
                    }
                }
                Button(action: begin) {
                    Label("Démarrer maintenant", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("En cours") {
                if model.running.isEmpty {
                    Text("Rien en cours.").foregroundStyle(.secondary)
                }
                ForEach(model.running) { e in
                    HStack {
                        Circle().fill(Theme.color(for: e.category)).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(e.title).lineLimit(1)
                            Text("depuis \(e.start.formatted(date: .omitted, time: .shortened)) · \(DayLogic.formatDuration(model.now.timeIntervalSince(e.start)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.stop(e.id) } label: { Image(systemName: "stop.fill") }
                            .buttonStyle(.borderless).help("Terminer maintenant")
                    }
                }
            }

            Section("Bilan du jour") {
                let totals = DayLogic.totals(model.entries, on: model.day, now: model.now)
                if totals.isEmpty { Text("Aucune activité enregistrée.").foregroundStyle(.secondary) }
                ForEach(totals, id: \.category) { t in
                    HStack {
                        Circle().fill(Theme.color(for: t.category)).frame(width: 10, height: 10)
                        Text(t.category)
                        Spacer()
                        Text(DayLogic.formatDuration(t.duration)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func begin() {
        model.start(title: title, category: category)
        title = ""
        model.day = Date()
    }
}
