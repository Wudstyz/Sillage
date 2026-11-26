import SwiftUI
import SillageCore

/// Récap de la journée : ce qui s'est passé, de telle heure à telle heure.
/// Calculé en continu à partir des données (aucune « clôture ») : toujours à jour, pour aujourd'hui comme pour un jour passé.
struct RecapView: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false

    var body: some View {
        let recap = Recap.build(model.shownEntries, on: model.day, now: model.now)
        let text = Recap.markdown(recap, now: model.now)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(recap, text: text)
                if recap.isEmpty {
                    empty
                } else {
                    cards(recap)
                    if !recap.segments.isEmpty { journey(recap) }
                    if !recap.appointments.isEmpty { appointments(recap) }
                    if !recap.categories.isEmpty { categories(recap) }
                    if !recap.tasks.isEmpty { tasks(recap) }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    // MARK: En-tête

    private func header(_ recap: DayRecap, text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recap.day.formatted(.dateTime.weekday(.wide)).capitalized).sectionLabel()
                Text(recap.day.formatted(.dateTime.day().month(.wide).year()))
                    .font(Theme.rounded(30, .bold)).foregroundStyle(Theme.ink)
            }
            Spacer()
            if !recap.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(ChipButtonStyle(category: "Autre"))
                .help("Copier le récap en texte (pour un mail, une note, une facture…)")
                ShareLink(item: text) { Label("Partager", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ChipButtonStyle(category: "Autre"))
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft").font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text("Rien d'enregistré ce jour-là.").font(Theme.rounded(15, .semibold)).foregroundStyle(Theme.ink)
            Text("Démarrez une tâche ou ajoutez une activité passée : le récap se construit tout seul.")
                .font(Theme.rounded(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: Chiffres clés

    private func cards(_ recap: DayRecap) -> some View {
        let time: (Date?) -> String = { $0?.formatted(date: .omitted, time: .shortened) ?? "—" }
        let done = recap.appointments.filter { if case .honored = $0.status { return true }; return $0.status == .covered }.count
        return HStack(spacing: 12) {
            StatCard(label: "Enregistré", value: DayLogic.formatDuration(recap.tracked))
            StatCard(label: "Début", value: time(recap.firstStart))
            StatCard(label: "Fin", value: recap.isStillRunning ? "en cours" : time(recap.lastEnd))
            if !recap.appointments.isEmpty {
                StatCard(label: "Rendez-vous", value: "\(done) / \(recap.appointments.count)")
            }
        }
    }

    // MARK: Journée

    private func journey(_ recap: DayRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Votre journée").sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(recap.segments.enumerated()), id: \.element.id) { index, seg in
                    segmentRow(seg)
                    if index < recap.segments.count - 1 { Divider().padding(.leading, 140) }
                }
            }
            .card(padding: 6)
        }
    }

    private func segmentRow(_ seg: RecapSegment) -> some View {
        let color = seg.isGap ? Theme.muted : Theme.color(for: seg.category)
        let range = seg.isLive
            ? "\(seg.start.formatted(date: .omitted, time: .shortened)) – …"
            : "\(seg.start.formatted(date: .omitted, time: .shortened)) – \(seg.end.formatted(date: .omitted, time: .shortened))"
        return Button {
            if let first = seg.entries.first { model.editor = AppModel.EditorTarget(entry: first, isNew: false) }
        } label: {
            HStack(spacing: 12) {
                Text(range).font(Theme.rounded(13, .semibold)).monospacedDigit()
                    .foregroundStyle(seg.isGap ? Theme.muted : Theme.ink).frame(width: 118, alignment: .leading)
                Capsule().fill(color.opacity(seg.isGap ? 0.35 : 1)).frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    if seg.isGap {
                        Text("Non renseigné").font(Theme.rounded(14, .medium)).italic().foregroundStyle(Theme.muted)
                    } else {
                        Text(seg.title).font(Theme.rounded(15, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(seg.entries.count > 1
                             ? "\(seg.entries.count) tâches simultanées · temps réparti"
                             : seg.category)
                            .font(Theme.rounded(12)).foregroundStyle(Theme.muted)
                        ForEach(seg.notes, id: \.self) { note in
                            Text(note).font(Theme.rounded(12)).italic().foregroundStyle(Theme.muted).lineLimit(2)
                        }
                    }
                }
                Spacer()
                if seg.isLive {
                    HStack(spacing: 4) {
                        PulsingDot(color: Theme.accent)
                        Text("en cours").font(Theme.rounded(11, .bold)).foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.accent.opacity(0.12)))
                }
                Text(DayLogic.formatDuration(seg.duration)).font(Theme.rounded(13, .semibold)).monospacedDigit()
                    .foregroundStyle(seg.isGap ? Theme.muted : Theme.ink).frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(seg.isGap)
    }

    // MARK: Rendez-vous

    private func appointments(_ recap: DayRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rendez-vous").sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(recap.appointments.enumerated()), id: \.element.id) { index, a in
                    Button { model.editor = AppModel.EditorTarget(entry: a.entry, isNew: false) } label: {
                        HStack(spacing: 12) {
                            Text(a.entry.start.formatted(date: .omitted, time: .shortened))
                                .font(Theme.rounded(13, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                                .frame(width: 118, alignment: .leading)
                            Circle().fill(Theme.color(for: a.entry.category)).frame(width: 10, height: 10)
                            Text(a.entry.title).font(Theme.rounded(15, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            statusBadge(a.status)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < recap.appointments.count - 1 { Divider().padding(.leading, 140) }
                }
            }
            .card(padding: 6)
        }
    }

    private func statusBadge(_ status: AppointmentStatus) -> some View {
        let (text, symbol, color): (String, String, Color)
        switch status {
        case .honored(let punctuality):
            (text, symbol, color) = (punctuality.isEmpty ? "Honoré" : "Honoré · \(punctuality)", "checkmark.circle.fill", Theme.color(for: "Loisirs"))
        case .covered: (text, symbol, color) = ("Couvert par vos activités", "checkmark.circle", Theme.color(for: "Travail"))
        case .missed: (text, symbol, color) = ("Sans trace", "questionmark.circle", Theme.danger)
        case .upcoming: (text, symbol, color) = ("À venir", "clock", Theme.muted)
        case .ongoing: (text, symbol, color) = ("En cours, pas encore pointé", "hourglass", Theme.warning)
        }
        return Label(text, systemImage: symbol).font(Theme.rounded(12, .semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: Temps par catégorie

    private func categories(_ recap: DayRecap) -> some View {
        let total = recap.categories.reduce(0) { $0 + $1.duration }
        let slices = recap.categories.map { DonutSlice(id: $0.category, label: $0.category, value: $0.duration, color: Theme.color(for: $0.category)) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Temps par catégorie").sectionLabel()
            HStack(alignment: .center, spacing: 24) {
                DonutChart(slices: slices, centerTitle: DayLogic.formatDuration(total), centerSubtitle: "enregistrées", lineWidth: 30)
                    .frame(width: 190, height: 190)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recap.categories, id: \.category) { c in
                        Button { model.openCategory(c.category) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Theme.color(for: c.category)).frame(width: 10, height: 10)
                                Text(c.category).font(Theme.rounded(14, .medium)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(total > 0 ? Int((c.duration / total * 100).rounded()) : 0) %").font(Theme.rounded(12))
                                    .foregroundStyle(Theme.muted).monospacedDigit()
                                Text(DayLogic.formatDuration(c.duration)).font(Theme.rounded(13, .semibold)).monospacedDigit()
                                    .foregroundStyle(Theme.ink).frame(width: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("Voir le détail de « \(c.category) »")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card()
        }
    }

    // MARK: Temps par tâche

    private func tasks(_ recap: DayRecap) -> some View {
        let maxValue = recap.tasks.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("Temps par tâche").sectionLabel()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(recap.tasks, id: \.title) { t in
                    Button { model.openTask(t.title) } label: {
                        VStack(spacing: 5) {
                            HStack {
                                Circle().fill(Theme.color(for: t.category)).frame(width: 9, height: 9)
                                Text(t.title).font(Theme.rounded(14, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer()
                                Text(DayLogic.formatDuration(t.duration)).font(Theme.rounded(14, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.color(for: t.category).opacity(0.14))
                                    Capsule().fill(Theme.color(for: t.category)).frame(width: max(6, geo.size.width * t.duration / maxValue))
                                }
                            }.frame(height: 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Voir le détail de « \(t.title) »")
                }
                if recap.hasSimultaneous {
                    Label("Tâches simultanées : le temps est réparti entre elles.", systemImage: "square.stack.3d.up")
                        .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}
