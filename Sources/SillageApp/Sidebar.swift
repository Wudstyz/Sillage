import SwiftUI
import SillageCore

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @State private var title = ""
    @State private var category = "Travail"
    @AppStorage("stopRunningOnStart") private var stopRunning = true

    var body: some View {
        List {
            Section("Je commence") {
                TextField("Que faites-vous ?", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(begin)
                Picker("Catégorie", selection: $category) {
                    ForEach(Categories.all, id: \.self) { c in
                        Label(c, systemImage: "circle.fill").foregroundStyle(Theme.color(for: c)).tag(c)
                    }
                }
                if !model.running.isEmpty {
                    Toggle("Terminer la tâche en cours", isOn: $stopRunning)
                        .help("Passer d'une tâche à l'autre : la précédente s'arrête à l'instant où la nouvelle commence.")
                }
                Button(action: begin) {
                    Label("Démarrer maintenant", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Raccourcis") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Preset.defaults, id: \.title) { p in
                        Button {
                            model.start(title: p.title, category: p.category)
                            model.day = Date()
                        } label: {
                            Label(p.title, systemImage: p.symbol).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.color(for: p.category))
                        .help("Démarrer « \(p.title) » maintenant")
                    }
                }
                .padding(.vertical, 2)
            }

            Section("En cours") {
                if model.running.isEmpty {
                    Text("Rien en cours.").foregroundStyle(.secondary)
                }
                ForEach(model.running) { e in
                    let forgotten = DayLogic.isLikelyForgotten(e, now: model.now)
                    VStack(alignment: .leading, spacing: 6) {
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
                    if forgotten {
                        Label("En cours depuis \(DayLogic.formatDuration(model.now.timeIntervalSince(e.start))) : oubliée ?",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Indiquer l'heure de fin…") { model.fixEnd(of: e) }
                            .controlSize(.small)
                    }
                    }
                }
            }

            Section(model.periodBilanTitle) {
                let totals = model.periodTotals()
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
        model.start(title: title, category: category, stopRunning: stopRunning)
        title = ""
        model.day = Date()
    }
}
