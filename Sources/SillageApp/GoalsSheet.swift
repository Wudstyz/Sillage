import SwiftUI
import SillageCore

extension GoalProgress {
    var periodWord: String {
        switch goal.period { case .day: return "par jour"; case .week: return "par semaine"; case .month: return "par mois" }
    }

    /// Couleur d'état : vert = atteint, rouge = limite dépassée, sinon la couleur de la tâche ou de la catégorie.
    var tint: Color {
        switch state {
        case .reached: return Theme.color(for: "Loisirs")
        case .exceeded: return Theme.danger
        case .inProgress:
            // Une limite presque atteinte (80 % et plus) passe en orange avant d'être dépassée.
            if goal.kind == .atMost && fraction >= 0.8 { return Theme.warning }
            return Theme.color(for: goal.category ?? "Travail")
        }
    }

    var summary: String {
        let verb = goal.kind == .atLeast ? "Objectif" : "Limite"
        return "\(verb) : \(DayLogic.formatDuration(goal.target)) \(periodWord)"
    }

    /// Phrase d'avancement (« Reste 12 h 30 », « Objectif atteint », « Limite dépassée de 1 h »…).
    var caption: String {
        switch state {
        case .reached: return "Objectif atteint"
        case .exceeded: return "Limite dépassée de \(DayLogic.formatDuration(done - goal.target))"
        case .inProgress:
            if goal.kind == .atMost { return "Encore \(DayLogic.formatDuration(remaining)) avant la limite" }
            if let pace = perRemainingDay { return "Reste \(DayLogic.formatDuration(remaining)) · environ \(DayLogic.formatDuration(pace)) par jour restant" }
            return "Reste \(DayLogic.formatDuration(remaining))"
        }
    }
}

/// Une ligne d'objectif : titre, avancement et jauge.
struct GoalProgressRow: View {
    let progress: GoalProgress
    var showCaption = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if progress.state == .reached { Image(systemName: "checkmark.circle.fill").foregroundStyle(progress.tint) }
                if progress.state == .exceeded { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(progress.tint) }
                Text(progress.goal.title).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Text("\(DayLogic.formatDuration(progress.done)) / \(DayLogic.formatDuration(progress.goal.target))")
                    .font(Theme.rounded(12, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(progress.tint.opacity(0.15))
                    Capsule().fill(progress.tint).frame(width: max(6, geo.size.width * min(1, progress.fraction)))
                }
            }
            .frame(height: 6)
            if showCaption {
                Text("\(progress.summary) · \(progress.caption)").font(Theme.rounded(11)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Fenêtre « Objectifs » : voir l'avancement, en ajouter, modifier, supprimer.
struct GoalsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Goal?
    @State private var onTask = true            // la cible est une tâche (sinon une catégorie)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "target").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Objectifs").font(Theme.rounded(22, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Fixez un temps à atteindre (« au moins ») ou à ne pas dépasser (« au plus ») sur une tâche ou une catégorie, par jour, semaine ou mois. L'avancement suit la période en cours.")
                .font(Theme.rounded(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)

            if let goal = editing { form(goal) }

            let progress = model.goalProgress()
            VStack(alignment: .leading, spacing: 12) {
                if progress.isEmpty && editing == nil {
                    Text("Aucun objectif pour l'instant.").font(Theme.rounded(13)).foregroundStyle(Theme.muted)
                }
                ForEach(progress) { p in
                    HStack(alignment: .top, spacing: 10) {
                        GoalProgressRow(progress: p)
                        VStack(spacing: 6) {
                            Button { edit(p.goal) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Modifier")
                            Button { model.deleteGoal(p.goal.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Supprimer")
                        }
                    }
                    if p.id != progress.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            if editing == nil {
                Button { edit(Goal(taskKey: nil, title: "", hours: 10, period: .week)) } label: { Label("Ajouter un objectif", systemImage: "plus") }
                    .buttonStyle(AccentButtonStyle(compact: true))
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .onAppear {
            if let draft = model.goalDraft { edit(draft); model.goalDraft = nil }
        }
    }

    private func edit(_ goal: Goal) {
        onTask = goal.category == nil
        editing = goal
    }

    // MARK: Formulaire

    private func form(_ goal: Goal) -> some View {
        let known = Array(Reports.summaries(model.entries, days: Reports.days(for: .all, anchor: model.now, entries: model.entries, now: model.now),
                                            now: model.now).prefix(8))
        let valid = goal.hours > 0 && !(goal.title.trimmingCharacters(in: .whitespaces).isEmpty)
        return VStack(alignment: .leading, spacing: 12) {
            Text(model.goals.contains { $0.id == goal.id } ? "Modifier l'objectif" : "Nouvel objectif").sectionLabel()

            Picker("Cible", selection: Binding(get: { onTask }, set: { on in
                onTask = on
                var g = goal
                if on { g.category = nil; g.taskKey = DayLogic.taskKey(g.title) } else { g.taskKey = nil; g.category = Categories.all.first; g.title = g.category ?? "" }
                editing = g
            })) {
                Text("Une tâche").tag(true)
                Text("Une catégorie").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()

            if onTask {
                TextField("Nom de la tâche (ex. SFCO)", text: Binding(get: { goal.title }, set: {
                    var g = goal; g.title = $0; g.taskKey = DayLogic.taskKey($0); editing = g
                })).textFieldStyle(.roundedBorder)
                if !known.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(known) { s in
                            Button(s.title) { var g = goal; g.title = s.title; g.taskKey = s.key; editing = g }
                                .buttonStyle(ChipButtonStyle(category: s.category)).lineLimit(1)
                        }
                    }
                }
            } else {
                Picker("Catégorie", selection: Binding(get: { goal.category ?? Categories.all[0] }, set: {
                    var g = goal; g.category = $0; g.title = $0; editing = g
                })) { ForEach(Categories.all, id: \.self) { Text($0).tag($0) } }
            }

            HStack(spacing: 12) {
                Picker("", selection: Binding(get: { goal.kind }, set: { var g = goal; g.kind = $0; editing = g })) {
                    Text("Au moins").tag(GoalKind.atLeast)
                    Text("Au plus").tag(GoalKind.atMost)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                Stepper(value: Binding(get: { goal.hours }, set: { var g = goal; g.hours = $0; editing = g }), in: 0.5...400, step: 0.5) {
                    Text(hoursText(goal.hours)).font(Theme.rounded(14, .semibold)).monospacedDigit()
                }
                Picker("", selection: Binding(get: { goal.period }, set: { var g = goal; g.period = $0; editing = g })) {
                    Text("par jour").tag(GoalPeriod.day)
                    Text("par semaine").tag(GoalPeriod.week)
                    Text("par mois").tag(GoalPeriod.month)
                }.labelsHidden().frame(width: 130)
            }

            HStack {
                Spacer()
                Button("Annuler") { editing = nil }
                Button("Enregistrer") {
                    var g = goal
                    g.title = g.title.trimmingCharacters(in: .whitespaces)
                    model.saveGoal(g)
                    editing = nil
                }.buttonStyle(AccentButtonStyle(compact: true)).disabled(!valid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func hoursText(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h)) h" : "\(Int(h)) h 30"
    }
}
