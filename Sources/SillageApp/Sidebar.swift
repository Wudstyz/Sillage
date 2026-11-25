import SwiftUI
import SillageCore

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @State private var title = ""
    @State private var category = "Travail"
    @AppStorage("stopRunningOnStart") private var stopRunning = true
    @AppStorage("bilanByTask") private var bilanByTask = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                brand
                nowSection
                startSection
                recentsSection
                shortcutsSection
                bilanSection
                VStack(spacing: 8) {
                    calendarsFooter
                    backupFooter
                }
            }
            .padding(16)
        }
        .background(Theme.panel)
    }

    // MARK: Marque

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 34, height: 34)
            Text("Sillage").font(Theme.rounded(22, .bold)).foregroundStyle(Theme.ink)
        }
    }

    // MARK: En cours

    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("En cours").sectionLabel()
            if model.running.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz").font(.system(size: 18)).foregroundStyle(Theme.muted)
                    Text("Rien en cours.\nDémarrez une tâche pour suivre votre journée.")
                        .font(Theme.rounded(12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
            }
            ForEach(model.running) { e in runningCard(e) }
        }
    }

    private func runningCard(_ e: Entry) -> some View {
        let color = Theme.color(for: e.category)
        let forgotten = DayLogic.isLikelyForgotten(e, now: model.now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PulsingDot(color: color)
                Text(e.title).font(Theme.rounded(15, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Button { model.stop(e.id) } label: { Image(systemName: "stop.fill").font(.system(size: 11)) }
                    .buttonStyle(StopButtonStyle()).help("Terminer maintenant")
            }
            Text(clockString(model.now.timeIntervalSince(e.start)))
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
            Text("depuis \(e.start.formatted(date: .omitted, time: .shortened)) · \(e.category)")
                .font(Theme.rounded(12)).foregroundStyle(Theme.muted)
            if forgotten {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Oubliée ? En cours depuis \(DayLogic.formatDuration(model.now.timeIntervalSince(e.start))).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.warning)
                    Button("Indiquer l'heure de fin…") { model.fixEnd(of: e) }.controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
        .overlay(alignment: .leading) {
            Capsule().fill(color).frame(width: 4).padding(.vertical, 12).padding(.leading, 5)
        }
    }

    // MARK: Démarrer

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Je commence").sectionLabel()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line").foregroundStyle(Theme.muted)
                    TextField("Que faites-vous ?", text: $title).textFieldStyle(.plain)
                        .font(Theme.rounded(14)).onSubmit(begin)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line))

                Menu {
                    ForEach(Categories.all, id: \.self) { c in Button(c) { category = c } }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.color(for: category)).frame(width: 10, height: 10)
                        Text(category).font(Theme.rounded(13, .medium))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.color(for: category).opacity(0.12)))
                }
                .buttonStyle(.plain).menuIndicator(.hidden)

                if !model.running.isEmpty {
                    Toggle(isOn: $stopRunning) {
                        Text("Terminer la tâche en cours").font(Theme.rounded(12)).foregroundStyle(Theme.muted)
                    }
                    .toggleStyle(.checkbox)
                    .help("Passer d'une tâche à l'autre : la précédente s'arrête à l'instant où la nouvelle commence.")
                }

                Button(action: begin) {
                    Label("Démarrer maintenant", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .card()
        }
    }

    // MARK: Sauvegarde

    private var calendarsFooter: some View {
        Button { model.showCalendars = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.color(for: "Calendrier"))
                Text(model.calendars.enabled && model.calendars.access == .granted ? "Calendriers affichés" : "Calendriers Mac et Google")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Afficher vos rendez-vous de Calendrier / Google (optionnel, ⇧⌘K)")
    }

    private var backupFooter: some View {
        Button { model.showBackup = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(Theme.color(for: "Loisirs"))
                Text(model.lastBackup.map { "Copie de secours à \($0.formatted(date: .omitted, time: .shortened))" }
                     ?? "Sauvegarde et export…")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sauvegarde automatique, export et restauration (⇧⌘B)")
    }

    // MARK: Récents

    @ViewBuilder private var recentsSection: some View {
        let recents = Array(model.recents.prefix(5))
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Récents").sectionLabel()
                VStack(spacing: 6) {
                    ForEach(recents, id: \.title) { r in
                        Button {
                            model.start(title: r.title, category: r.category)
                            model.day = Date()
                        } label: {
                            Label(r.title, systemImage: "arrow.counterclockwise").lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ChipButtonStyle(category: r.category))
                        .help("Reprendre « \(r.title) » maintenant")
                    }
                }
            }
        }
    }

    // MARK: Raccourcis

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raccourcis").sectionLabel()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(Preset.defaults, id: \.title) { p in
                    Button {
                        model.start(title: p.title, category: p.category)
                        model.day = Date()
                    } label: {
                        Label(p.title, systemImage: p.symbol).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(ChipButtonStyle(category: p.category))
                    .help("Démarrer « \(p.title) » maintenant")
                }
            }
        }
    }

    // MARK: Bilan

    private var bilanSection: some View {
        let rows: [(name: String, category: String, duration: TimeInterval)] = bilanByTask
            ? model.periodTaskTotals().map { ($0.title, $0.category, $0.duration) }
            : model.periodTotals().map { ($0.category, $0.category, $0.duration) }
        let maxValue = rows.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text(model.periodBilanTitle).sectionLabel()
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $bilanByTask) {
                    Text("Catégories").tag(false)
                    Text("Tâches").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
                if rows.isEmpty {
                    Text("Aucune activité enregistrée.").font(Theme.rounded(12)).foregroundStyle(Theme.muted)
                }
                if model.periodHasSimultaneous() {
                    Label("Tâches simultanées : le temps est réparti entre elles.", systemImage: "square.stack.3d.up")
                        .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.muted)
                }
                ForEach(Array(rows.prefix(bilanByTask ? 8 : 12).enumerated()), id: \.offset) { _, row in
                    let content = VStack(spacing: 5) {
                        HStack {
                            Text(row.name).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            Text(DayLogic.formatDuration(row.duration)).font(Theme.rounded(13, .semibold))
                                .monospacedDigit().foregroundStyle(Theme.ink)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.color(for: row.category).opacity(0.14))
                                Capsule().fill(Theme.color(for: row.category))
                                    .frame(width: max(6, geo.size.width * row.duration / maxValue))
                            }
                        }
                        .frame(height: 6)
                    }
                    if bilanByTask {
                        Button { model.openTask(row.name) } label: { content.contentShape(Rectangle()) }
                            .buttonStyle(.plain).help("Voir le détail de « \(row.name) »")
                    } else {
                        content
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func begin() {
        model.start(title: title, category: category)
        title = ""
    }
}
