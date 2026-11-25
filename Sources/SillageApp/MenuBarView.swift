import SwiftUI
import SillageCore

/// Titre affiché dans la barre de menus : une icône, et la tâche en cours avec son chronomètre.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let first = model.running.first {
            let extra = model.running.count > 1 ? " +\(model.running.count - 1)" : ""
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                Text("\(first.title) · \(DayLogic.formatDuration(model.now.timeIntervalSince(first.start)))\(extra)")
            }
        } else {
            Image(systemName: "clock")
        }
    }
}

/// Panneau de la barre de menus : voir ce qui tourne, démarrer ou arrêter sans ouvrir la fenêtre.
struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var title = ""
    @State private var category = "Travail"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 24, height: 24)
                Text("Sillage").font(Theme.rounded(17, .bold)).foregroundStyle(Theme.ink)
            }

            if let next = Actions.nextPlanned(model.shownEntries, now: model.now) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prochain rendez-vous").sectionLabel()
                    HStack {
                        Circle().fill(Theme.color(for: next.category)).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(next.title).lineLimit(1)
                            Text("\(next.start.formatted(date: .omitted, time: .shortened)) · \(Actions.countdown(to: next, now: model.now))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("J'y suis") { model.arrive(at: next) }.buttonStyle(AccentButtonStyle(compact: true))
                    }
                }
                Divider()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("En cours").sectionLabel()
                if model.running.isEmpty { Text("Rien en cours.").foregroundStyle(.secondary) }
                ForEach(model.running) { e in
                    HStack {
                        Circle().fill(Theme.color(for: e.category)).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(e.title).lineLimit(1)
                            Text("depuis \(e.start.formatted(date: .omitted, time: .shortened)) · \(DayLogic.formatDuration(model.now.timeIntervalSince(e.start)))")
                                .font(.caption)
                                .foregroundStyle(DayLogic.isLikelyForgotten(e, now: model.now) ? .orange : .secondary)
                        }
                        Spacer()
                        Button { model.stop(e.id) } label: { Image(systemName: "stop.fill").font(.system(size: 10)) }
                            .buttonStyle(StopButtonStyle()).help("Terminer maintenant")
                    }
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Je commence").sectionLabel()
                HStack {
                    TextField("Que faites-vous ?", text: $title).textFieldStyle(.plain).onSubmit(begin)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.background))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line))
                    Button(action: begin) { Image(systemName: "play.fill") }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.recents.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(Array(model.recents.prefix(4)), id: \.title) { r in
                            Button { model.start(title: r.title, category: r.category) } label: {
                                Label(r.title, systemImage: "arrow.counterclockwise").font(.caption).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(ChipButtonStyle(category: r.category))
                            .help("Reprendre « \(r.title) »")
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(Preset.defaults, id: \.title) { p in
                        Button { model.start(title: p.title, category: p.category) } label: {
                            Label(p.title, systemImage: p.symbol).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ChipButtonStyle(category: p.category))
                    }
                }
            }
            Divider()

            HStack {
                Button("Ouvrir Sillage") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(Theme.panel)
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }

    private func begin() {
        model.start(title: title, category: category)
        title = ""
    }
}
