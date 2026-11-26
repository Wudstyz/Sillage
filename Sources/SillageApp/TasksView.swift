import SwiftUI
import Charts
import SillageCore

/// Vue Bilan : combien de temps par tâche, ou par catégorie, pour un jour, une semaine, un mois ou depuis toujours.
struct TasksView: View {
    @EnvironmentObject var model: AppModel
    private var showCategories: Bool {
        get { model.showCategories }
        nonmutating set { model.showCategories = newValue }
    }
    @State private var renaming: TaskSummary?

    var body: some View {
        VStack(spacing: 0) {
            if showCategories {
                let cats = model.categorySummaries()
                let total = cats.reduce(0) { $0 + $1.total }
                periodBar(total: total, count: cats.count, noun: "catégorie")
                let selected = cats.first { $0.category == model.selectedCategory }
                HStack(spacing: 0) {
                    categoryList(cats, selected: selected, total: total).frame(width: 330)
                    Rectangle().fill(Theme.line).frame(width: 1)
                    if let selected { categoryDetail(selected, total: total) } else { overview(tasks: [], cats: cats, total: total) }
                }
            } else {
                let summaries = model.taskSummaries()
                periodBar(total: summaries.reduce(0) { $0 + $1.total }, count: summaries.count, noun: "tâche")
                let selected = summaries.first { $0.key == model.selectedTask }
                HStack(spacing: 0) {
                    list(summaries, selected: selected).frame(width: 330)
                    Rectangle().fill(Theme.line).frame(width: 1)
                    if let selected { detail(selected) } else { overview(tasks: summaries, cats: model.categorySummaries(), total: summaries.reduce(0) { $0 + $1.total }) }
                }
            }
        }
        .background(Theme.background)
        .sheet(item: $renaming) { RenameTaskSheet(task: $0) }
        .onChange(of: model.renameRequest) { key in openRename(key) }
        .onAppear {
            if !model.bilanKeepSelection { model.selectedTask = nil; model.selectedCategory = nil }
            model.bilanKeepSelection = false
            openRename(model.renameRequest)
        }
    }

    private func openRename(_ key: String?) {
        guard let key, let task = model.taskSummaries().first(where: { $0.key == key }) else { return }
        showCategories = false
        renaming = task
        model.renameRequest = nil
    }

    // MARK: Barre de période

    private func periodBar(total: TimeInterval, count: Int, noun: String) -> some View {
        HStack(spacing: 12) {
            Picker("Regrouper par", selection: $model.showCategories) {
                Text("Tâches").tag(false)
                Text("Catégories").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            .help("Voir le temps par tâche ou par catégorie")
            Picker("Période", selection: $model.reportPeriod) {
                ForEach(ReportPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            Spacer()
            Picker("Temps simultané", selection: $model.cumulativeTime) {
                Text("Réparti").tag(false)
                Text("Cumulé").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            .help("Temps simultané : réparti entre les tâches (le total est le temps écoulé), ou cumulé (chaque tâche compte tout son temps, le total peut dépasser 24 h)")
            if count > 0 {
                Text("\(DayLogic.formatDuration(total)) · \(count) \(noun)\(count > 1 ? "s" : "")")
                    .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    // MARK: - Tâches

    private func list(_ summaries: [TaskSummary], selected: TaskSummary?) -> some View {
        let maxTotal = summaries.map(\.total).max() ?? 1
        return ScrollView {
            VStack(spacing: 8) {
                overviewRow(selected: selected == nil) { model.selectedTask = nil }
                if summaries.isEmpty { emptyList("Aucune tâche sur cette période.") }
                ForEach(summaries) { s in
                    row(color: Theme.color(for: s.category), title: s.title, trailing: DayLogic.formatDuration(s.total),
                        fraction: s.total / maxTotal, selected: s.key == selected?.key) { model.selectedTask = s.key }
                }
            }
            .padding(14)
        }
    }

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
                    firstLast(s.first, s.last, noun: "séance")
                    goalsSection(model.goalProgress(forTask: s.key))
                    chart(perDay: s.perDay, color: color)
                    sessionsList(Reports.sessions(of: s.key, in: model.entries, days: model.periodDays), showTitle: false)
                }
                .padding(20)
            }
        } else {
            emptyDetail("Choisissez une tâche pour voir son détail.")
        }
    }

    // MARK: - Catégories

    private func categoryList(_ cats: [CategorySummary], selected: CategorySummary?, total: TimeInterval) -> some View {
        let maxTotal = cats.map(\.total).max() ?? 1
        return ScrollView {
            VStack(spacing: 8) {
                overviewRow(selected: selected == nil) { model.selectedCategory = nil }
                if cats.isEmpty { emptyList("Aucune catégorie sur cette période.") }
                ForEach(cats) { c in
                    row(color: Theme.color(for: c.category), title: c.category,
                        trailing: "\(percent(c.total, of: total)) · \(DayLogic.formatDuration(c.total))",
                        fraction: c.total / maxTotal, selected: c.category == selected?.category) { model.selectedCategory = c.category }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder private func categoryDetail(_ c: CategorySummary?, total: TimeInterval) -> some View {
        if let c {
            let color = Theme.color(for: c.category)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Circle().fill(color).frame(width: 16, height: 16)
                        Text(c.category).font(Theme.rounded(28, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("\(c.tasks.count) tâche\(c.tasks.count > 1 ? "s" : "")")
                            .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.ink(for: c.category))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.14)))
                        Spacer()
                        Button { model.newGoal(forCategory: c.category) } label: { Label("Objectif…", systemImage: "target") }
                            .buttonStyle(ChipButtonStyle(category: c.category)).help("Fixer un temps à atteindre ou à ne pas dépasser sur cette catégorie")
                    }

                    HStack(spacing: 12) {
                        stat("Temps total", DayLogic.formatDuration(c.total))
                        stat("Part du temps", percent(c.total, of: total))
                        stat("Séances", "\(c.sessions)")
                        stat("Moy. / jour", DayLogic.formatDuration(c.averagePerActiveDay))
                    }
                    firstLast(c.first, c.last, noun: "séance")
                    goalsSection(model.goalProgress(forCategory: c.category))
                    chart(perDay: c.perDay, color: color)
                    tasksInCategory(c)
                    sessionsList(Reports.sessions(ofCategory: c.category, in: model.entries, days: model.periodDays), showTitle: true)
                }
                .padding(20)
            }
        } else {
            emptyDetail("Choisissez une catégorie pour voir son détail.")
        }
    }

    /// Les tâches qui composent la catégorie ; un clic ouvre la tâche.
    private func tasksInCategory(_ c: CategorySummary) -> some View {
        let maxValue = c.tasks.map(\.duration).max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tâches de cette catégorie").sectionLabel()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(c.tasks, id: \.title) { t in
                    Button { model.openTask(t.title) } label: {
                        VStack(spacing: 5) {
                            HStack {
                                Text(t.title).font(Theme.rounded(14, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer()
                                Text("\(percent(t.duration, of: c.total)) · \(DayLogic.formatDuration(t.duration))")
                                    .font(Theme.rounded(13, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.color(for: c.category).opacity(0.14))
                                    Capsule().fill(Theme.color(for: c.category)).frame(width: max(6, geo.size.width * t.duration / maxValue))
                                }
                            }.frame(height: 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Voir le détail de « \(t.title) »")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Vue d'ensemble (par défaut : tout d'un coup d'œil)

    private func overviewRow(selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill").foregroundStyle(Theme.accent)
                Text("Vue d'ensemble").font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.accent.opacity(0.08) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Le camembert, sa légende, les chiffres clés et l'évolution dans le temps. Un clic sur une part ouvre son détail.
    @ViewBuilder private func overview(tasks: [TaskSummary], cats: [CategorySummary], total: TimeInterval) -> some View {
        if total <= 0 {
            emptyDetail("Rien d'enregistré sur cette période.")
        } else {
            let items: [(label: String, category: String, value: TimeInterval)] = showCategories
                ? cats.map { ($0.category, $0.category, $0.total) }
                : tasks.map { ($0.title, $0.category, $0.total) }
            let slices = ChartData.slices(items, maxSlices: showCategories ? 10 : 8)
            let donut = donutSlices(slices)
            let period = model.periodTitle.replacingOccurrences(of: "Bilan · ", with: "")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.pie.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                        Text("Vue d'ensemble").font(Theme.rounded(28, .bold)).foregroundStyle(Theme.ink)
                        Text(period).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Theme.ink.opacity(0.06)))
                        Spacer()
                    }

                    HStack(alignment: .center, spacing: 22) {
                        DonutChart(slices: donut, centerTitle: DayLogic.formatDuration(total), centerSubtitle: model.cumulativeTime ? "cumulées" : "enregistrées")
                            .frame(width: 220, height: 220)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(zip(slices, donut)), id: \.1.id) { slice, d in
                                legendRow(slice, color: d.color, total: total, tasks: tasks)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .card()

                    HStack(spacing: 12) {
                        let days = Set(cats.flatMap { $0.perDay.map(\.day) }).count
                        stat("Temps total", DayLogic.formatDuration(total))
                        stat("Moy. / jour", DayLogic.formatDuration(days > 0 ? total / Double(days) : 0))
                        stat("Tâches", "\(tasks.isEmpty ? Set(cats.flatMap { $0.tasks.map { DayLogic.taskKey($0.title) } }).count : tasks.count)")
                        stat("Catégories", "\(cats.count)")
                    }

                    stackedChart(cats)
                }
                .padding(20)
            }
        }
    }

    /// Couleurs du camembert : celle de la catégorie ; deux tâches de la même catégorie s'éclaircissent un peu pour se distinguer.
    private func donutSlices(_ slices: [ChartSlice]) -> [DonutSlice] {
        var seen: [String: Int] = [:]
        return slices.enumerated().map { index, s in
            guard let category = s.category else {
                return DonutSlice(id: "autres", label: s.label, value: s.value, color: Theme.muted.opacity(0.55))
            }
            let k = seen[category, default: 0]
            seen[category] = k + 1
            return DonutSlice(id: "\(index)-\(s.label)", label: s.label, value: s.value,
                              color: Theme.color(for: category).opacity(max(0.45, 1 - 0.2 * Double(k))))
        }
    }

    private func legendRow(_ slice: ChartSlice, color: Color, total: TimeInterval, tasks: [TaskSummary]) -> some View {
        let content = HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 11, height: 11).padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(slice.label).font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(percent(slice.value, of: total)) · \(DayLogic.formatDuration(slice.value))")
                    .font(Theme.rounded(12)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4).contentShape(Rectangle())
        return Group {
            if slice.isOther {
                content
            } else {
                Button {
                    if showCategories { model.selectedCategory = slice.label }
                    else if let t = tasks.first(where: { $0.title == slice.label }) { model.selectedTask = t.key }
                } label: { content }
                .buttonStyle(.plain).help("Voir le détail de « \(slice.label) »")
            }
        }
    }

    private struct StackBar: Identifiable { let id = UUID(); let date: Date; let category: String; let hours: Double }

    /// Temps par catégorie au fil du temps (une barre par jour, ou par semaine ou par mois sur une longue période), empilé.
    private func stackedChart(_ cats: [CategorySummary]) -> some View {
        let cal = Calendar.current
        let days = model.periodDays
        let unit: Calendar.Component = days.count <= 62 ? .day : (days.count <= 400 ? .weekOfYear : .month)
        func key(_ d: Date) -> Date { unit == .day ? d : (cal.dateInterval(of: unit, for: d)?.start ?? d) }
        var sums: [String: [Date: TimeInterval]] = [:]
        for c in cats { for t in c.perDay { sums[c.category, default: [:]][key(t.day), default: 0] += t.duration } }
        let data = cats.flatMap { c in (sums[c.category] ?? [:]).map { StackBar(date: $0.key, category: c.category, hours: $0.value / 3600) } }
        let title = unit == .day ? "Temps par jour" : (unit == .weekOfYear ? "Temps par semaine" : "Temps par mois")
        let bucketCount = Set(data.map(\.date)).count
        let singleBucket = bucketCount == 1
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            Chart(data) { b in
                BarMark(x: .value("Date", b.date, unit: unit), y: .value("Heures", b.hours))
                    .foregroundStyle(by: .value("Catégorie", b.category))
            }
            .chartForegroundStyleScale(domain: cats.map(\.category), range: cats.map { Theme.color(for: $0.category) })
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h)) h").font(Theme.rounded(10)) } }
                }
            }
            .chartXAxis {
                if singleBucket {
                    AxisMarks(values: Array(Set(data.map(\.date)))) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), anchor: .top).font(Theme.rounded(10))
                    }
                } else {
                    AxisMarks(values: unit == .day && bucketCount > 14 ? AxisMarkValues.stride(by: .day, count: 7) : .automatic) { _ in
                        AxisValueLabel(format: unit == .month ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated), anchor: .top)
                            .font(Theme.rounded(10))
                    }
                }
            }
            .frame(height: 220)
        }
        .card()
    }

    // MARK: - Éléments communs

    private func percent(_ part: TimeInterval, of total: TimeInterval) -> String {
        total > 0 ? "\(Int((part / total * 100).rounded())) %" : "0 %"
    }

    private func row(color: Color, title: String, trailing: String, fraction: Double, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(title).font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(trailing).font(Theme.rounded(13, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.14))
                        Capsule().fill(color).frame(width: max(6, geo.size.width * fraction))
                    }
                }.frame(height: 6)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.accent.opacity(0.08) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func emptyList(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(Theme.muted)
            Text(text).font(Theme.rounded(13)).foregroundStyle(Theme.muted)
        }.padding(.top, 40)
    }

    private func emptyDetail(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text(text).font(Theme.rounded(14)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func firstLast(_ first: Date?, _ last: Date?, noun: String) -> some View {
        if let first, let last {
            Text("Première \(noun) le \(first.formatted(date: .long, time: .omitted)), dernière le \(last.formatted(date: .long, time: .omitted)).")
                .font(Theme.rounded(12)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func goalsSection(_ goals: [GoalProgress]) -> some View {
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
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    // MARK: Graphique

    private struct Bar: Identifiable { let id: Date; let date: Date; let hours: Double }

    /// Une barre par jour ; par semaine ou par mois quand la période est longue.
    private func bars(_ perDay: [TaskDay]) -> (bars: [Bar], unit: Calendar.Component) {
        let cal = Calendar.current
        let days = model.periodDays
        let unit: Calendar.Component = days.count <= 62 ? .day : (days.count <= 400 ? .weekOfYear : .month)
        var sums: [Date: TimeInterval] = [:]
        for d in days {
            let key = unit == .day ? d : (cal.dateInterval(of: unit, for: d)?.start ?? d)
            sums[key, default: 0] += 0
        }
        for t in perDay {
            let key = unit == .day ? t.day : (cal.dateInterval(of: unit, for: t.day)?.start ?? t.day)
            sums[key, default: 0] += t.duration
        }
        return (sums.map { Bar(id: $0.key, date: $0.key, hours: $0.value / 3600) }.sorted { $0.date < $1.date }, unit)
    }

    private func chart(perDay: [TaskDay], color: Color) -> some View {
        let data = bars(perDay)
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
                // Une seule étiquette pour un seul jour ; une par semaine quand il y a beaucoup de jours, pour éviter les chevauchements.
                if data.bars.count == 1 {
                    AxisMarks(values: data.bars.map(\.date)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), anchor: .top).font(Theme.rounded(10))
                    }
                } else {
                    AxisMarks(values: data.unit == .day && data.bars.count > 14 ? AxisMarkValues.stride(by: .day, count: 7) : .automatic) { _ in
                        AxisValueLabel(format: data.unit == .month ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated),
                                       anchor: .top)
                            .font(Theme.rounded(10))
                    }
                }
            }
            .frame(height: 190)
        }
        .card()
    }

    // MARK: Séances

    private func sessionsList(_ all: [Entry], showTitle: Bool) -> some View {
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
                                if showTitle {
                                    Text(e.title).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                }
                                Spacer()
                                Text(rangeText(e)).font(Theme.rounded(13)).foregroundStyle(Theme.muted)
                                Text(DayLogic.formatDuration(e.effectiveEnd(now: model.now).timeIntervalSince(e.start)))
                                    .font(Theme.rounded(13, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                                    .frame(width: 70, alignment: .trailing)
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
