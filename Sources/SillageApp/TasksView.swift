import SwiftUI
import Charts
import SillageCore

/// Vue Tâches : combien de temps sur chaque tâche, pour un jour, une semaine, un mois ou depuis toujours.
struct TasksView: View {
    @EnvironmentObject var model: AppModel
    @State private var renaming: TaskSummary?

    var body: some View {
        let summaries = model.taskSummaries()
        let selected = summaries.first { $0.key == model.selectedTask } ?? summaries.first
        VStack(spacing: 0) {
            periodBar(summaries)
            HStack(spacing: 0) {
                list(summaries, selected: selected).frame(width: 330)
                Rectangle().fill(Theme.line).frame(width: 1)
                detail(selected)
            }
        }
        .background(Theme.background)
        .sheet(item: $renaming) { RenameTaskSheet(task: $0) }
        .onChange(of: model.renameRequest) { key in openRename(key) }
        .onAppear { openRename(model.renameRequest) }
    }

    private func openRename(_ key: String?) {
        guard let key, let task = model.taskSummaries().first(where: { $0.key == key }) else { return }
        renaming = task
        model.renameRequest = nil
    }

    // MARK: Barre de période

    private func periodBar(_ summaries: [TaskSummary]) -> some View {
        let total = summaries.reduce(0) { $0 + $1.total }
        return HStack {
            Picker("Période", selection: $model.reportPeriod) {
                ForEach(ReportPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            Spacer()
            if !summaries.isEmpty {
                Text("\(DayLogic.formatDuration(total)) · \(summaries.count) tâche\(summaries.count > 1 ? "s" : "")")
                    .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    // MARK: Liste des tâches

    private func list(_ summaries: [TaskSummary], selected: TaskSummary?) -> some View {
        let maxTotal = summaries.map(\.total).max() ?? 1
        return ScrollView {
            VStack(spacing: 8) {
                if summaries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(Theme.muted)
                        Text("Aucune tâche sur cette période.").font(Theme.rounded(13)).foregroundStyle(Theme.muted)
                    }.padding(.top, 40)
                }
                ForEach(summaries) { s in
                    let isSelected = s.key == selected?.key
                    Button { model.selectedTask = s.key } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Circle().fill(Theme.color(for: s.category)).frame(width: 10, height: 10)
                                Text(s.title).font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer()
                                Text(DayLogic.formatDuration(s.total)).font(Theme.rounded(13, .semibold))
                                    .monospacedDigit().foregroundStyle(Theme.ink)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.color(for: s.category).opacity(0.14))
                                    Capsule().fill(Theme.color(for: s.category))
                                        .frame(width: max(6, geo.size.width * s.total / maxTotal))
                                }
                            }.frame(height: 6)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Theme.accent.opacity(0.08) : Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    // MARK: Détail d'une tâche

    @ViewBuilder private func detail(_ s: TaskSummary?) -> some View {
        if let s {
            let color = Theme.color(for: s.category)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Circle().fill(color).frame(width: 16, height: 16)
                        Text(s.title).font(Theme.rounded(28, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                        Text(s.category).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.ink(for: s.category))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.14)))
                        Spacer()
                        Button { renaming = s } label: { Label("Renommer…", systemImage: "pencil") }
                            .buttonStyle(ChipButtonStyle(category: "Autre")).help("Renommer cette tâche partout, ou la fusionner avec une autre")
                        Button { model.newGoal(forTask: s.title) } label: { Label("Objectif…", systemImage: "target") }
                            .buttonStyle(ChipButtonStyle(category: s.category)).help("Fixer un temps à atteindre ou à ne pas dépasser")
                    }

                    HStack(spacing: 12) {
                        stat("Temps total", DayLogic.formatDuration(s.total))
                        stat("Séances", "\(s.sessions)")
                        stat("Jours actifs", "\(s.activeDays)")
                        stat("Moy. / jour", DayLogic.formatDuration(s.averagePerActiveDay))
                    }

                    if let first = s.first, let last = s.last {
                        Text("Première séance le \(first.formatted(date: .long, time: .omitted)), dernière le \(last.formatted(date: .long, time: .omitted)).")
                            .font(Theme.rounded(12)).foregroundStyle(Theme.muted)
                    }

                    goalsSection(s)
                    chart(s, color: color)
                    sessionsList(s)
                }
                .padding(20)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 34)).foregroundStyle(Theme.muted)
                Text("Choisissez une tâche pour voir son détail.").font(Theme.rounded(14)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func goalsSection(_ s: TaskSummary) -> some View {
        let goals = model.goalProgress(forTask: s.key)
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Objectifs").sectionLabel()
                    Spacer()
                    Button("Gérer…") { model.showGoals = true }.buttonStyle(.plain).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.accent)
                }
                ForEach(goals) { GoalProgressRow(progress: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabel().lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(Theme.rounded(22, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    // MARK: Graphique

    private struct Bar: Identifiable { let id: Date; let date: Date; let hours: Double }

    /// Une barre par jour ; par semaine ou par mois quand la période est longue.
    private func bars(_ s: TaskSummary) -> (bars: [Bar], unit: Calendar.Component) {
        let cal = Calendar.current
        let days = model.periodDays
        let unit: Calendar.Component = days.count <= 62 ? .day : (days.count <= 400 ? .weekOfYear : .month)
        var sums: [Date: TimeInterval] = [:]
        for d in days {
            let key = unit == .day ? d : (cal.dateInterval(of: unit, for: d)?.start ?? d)
            sums[key, default: 0] += 0
        }
        for t in s.perDay {
            let key = unit == .day ? t.day : (cal.dateInterval(of: unit, for: t.day)?.start ?? t.day)
            sums[key, default: 0] += t.duration
        }
        return (sums.map { Bar(id: $0.key, date: $0.key, hours: $0.value / 3600) }.sorted { $0.date < $1.date }, unit)
    }

    private func chart(_ s: TaskSummary, color: Color) -> some View {
        let data = bars(s)
        let title = data.unit == .day ? "Temps par jour" : (data.unit == .weekOfYear ? "Temps par semaine" : "Temps par mois")
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            Chart(data.bars) { b in
                BarMark(x: .value("Date", b.date, unit: data.unit), y: .value("Heures", b.hours))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h)) h").font(Theme.rounded(10)) } }
                }
            }
            .chartXAxis {
                // Une étiquette par semaine quand il y a beaucoup de jours, pour éviter les chevauchements.
                AxisMarks(values: data.unit == .day && data.bars.count > 14 ? .stride(by: .day, count: 7) : .automatic) { _ in
                    AxisValueLabel(format: data.unit == .month ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated),
                                   anchor: .top)
                        .font(Theme.rounded(10))
                }
            }
            .frame(height: 190)
        }
        .card()
    }

    // MARK: Séances

    private func sessionsList(_ s: TaskSummary) -> some View {
        let all = Reports.sessions(of: s.key, in: model.entries, days: model.periodDays)
        let shown = Array(all.prefix(40))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Séances").sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, e in
                    Button { model.editor = AppModel.EditorTarget(entry: e, isNew: false) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text(e.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.ink).frame(width: 110, alignment: .leading)
                            Text(rangeText(e)).font(Theme.rounded(13)).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(DayLogic.formatDuration(e.effectiveEnd(now: model.now).timeIntervalSince(e.start)))
                                .font(Theme.rounded(13, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                        }
                        if let note = e.trimmedNotes {
                            Text(note).font(Theme.rounded(12)).italic().foregroundStyle(Theme.muted).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        }
                        .padding(.vertical, 9).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < shown.count - 1 { Divider() }
                }
                if all.count > shown.count {
                    Text("… et \(all.count - shown.count) autres séances").font(Theme.rounded(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
            }
            .card(padding: 14)
        }
    }

    private func rangeText(_ e: Entry) -> String {
        let a = e.start.formatted(date: .omitted, time: .shortened)
        guard let end = e.end else { return "\(a) → en cours" }
        return "\(a) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}
