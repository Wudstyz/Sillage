import SwiftUI
import SillageCore

enum SeriesScope { case this, following }

struct EditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: AppModel.EditorTarget
    @State private var entry: Entry
    @State private var hasEnd: Bool
    @State private var end: Date
    // Répétition (nouvelle série)
    @State private var scope: SeriesScope = .this
    @State private var frequency: Recurrence.Frequency?
    @State private var interval = 1
    @State private var weekdays: Set<Int> = []
    @State private var hasUntil = false
    @State private var until = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    init(target: AppModel.EditorTarget) {
        self.target = target
        _entry = State(initialValue: target.entry)
        _hasEnd = State(initialValue: target.entry.end != nil)
        _end = State(initialValue: target.entry.end ?? Date())
        _weekdays = State(initialValue: [Calendar.current.component(.weekday, from: target.entry.start)])
        _until = State(initialValue: Calendar.current.date(byAdding: .month, value: 3, to: target.entry.start) ?? Date())
    }

    private var planned: Bool { entry.kind == .planned }
    private var valid: Bool {
        !entry.title.trimmingCharacters(in: .whitespaces).isEmpty && (!hasEnd || end > entry.start)
    }

    var body: some View {
        if target.entry.isExternal { externalBody } else { editorBody }
    }

    /// Rendez-vous venu d'un calendrier : en lecture seule, avec « J'y suis ».
    private var externalBody: some View {
        let e = target.entry
        let range = "\(e.start.formatted(date: .complete, time: .shortened)) – \((e.end ?? e.start).formatted(date: .omitted, time: .shortened))"
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "calendar").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.color(for: "Calendrier"))
                Text(e.title).font(Theme.rounded(20, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Calendrier") { Text(e.source ?? "").foregroundStyle(Theme.ink) }
                LabeledContent("Quand") { Text(range).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing) }
                if let p = model.punctuality(of: model.entries.first { $0.plannedID == e.id } ?? e) {
                    LabeledContent("Pointage") { Text("Honoré · \(p)").foregroundStyle(Theme.color(for: "Loisirs")) }
                }
            }
            .font(Theme.rounded(13))
            Text("Ce rendez-vous est lu dans votre calendrier : il est en lecture seule dans Sillage. Modifiez-le dans l'app Calendrier.")
                .font(Theme.rounded(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Ouvrir Calendrier") {
                    if let url = URL(string: "calshow:\(e.start.timeIntervalSinceReferenceDate)") { NSWorkspace.shared.open(url) }
                }.buttonStyle(ChipButtonStyle(category: "Autre"))
                Spacer()
                if !model.isArrived(e) {
                    Button("J'y suis") { model.arrive(at: e); dismiss() }.buttonStyle(AccentButtonStyle())
                }
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.background)
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(Theme.color(for: entry.category)).frame(width: 14, height: 14)
                Text(target.isNew ? (planned ? "Nouveau rendez-vous" : "Activité passée")
                                  : (planned ? "Rendez-vous" : "Activité"))
                    .font(Theme.rounded(20, .bold)).foregroundStyle(Theme.ink)
            }
            Form {
                TextField("Titre", text: $entry.title)
                Picker("Catégorie", selection: $entry.category) {
                    ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("Début", selection: $entry.start)
                if planned {
                    DatePicker("Fin", selection: $end)
                    Picker("Rappel", selection: $entry.reminderMinutes) {
                        ForEach(Reminders.options, id: \.label) { Text($0.label).tag($0.minutes) }
                    }
                    repeatSection
                } else {
                    Toggle("Terminée", isOn: $hasEnd)
                    if hasEnd { DatePicker("Fin", selection: $end) }
                }
                notesField
            }
            if hasEnd && end <= entry.start {
                Text("La fin doit être après le début.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                deleteControl
                if planned && !target.isNew && !model.isArrived(target.entry) {
                    Button("J'y suis") { model.arrive(at: target.entry); dismiss() }
                        .help("Démarrer maintenant la tâche réelle liée à ce rendez-vous")
                }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer", action: save).buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.background)
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { entry.notes ?? "" }, set: { entry.notes = $0.isEmpty ? nil : $0 }))
                .font(Theme.rounded(13))
                .frame(height: 64)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line))
        }
    }

    // MARK: Répétition

    private static let weekdayOrder: [(id: Int, letter: String)] =
        [(2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]

    @ViewBuilder private var repeatSection: some View {
        if let existing = model.series(of: entry) {
            LabeledContent("Série") { Text(Self.summary(existing.rule)).foregroundStyle(.secondary) }
            Picker("Appliquer à", selection: $scope) {
                Text("Cette occurrence").tag(SeriesScope.this)
                Text("Celle-ci et les suivantes").tag(SeriesScope.following)
            }
            .pickerStyle(.segmented)
            Text(scope == .this
                 ? "Seule cette occurrence est modifiée."
                 : "Le titre, l'heure, la durée, le rappel et la note changent aussi pour les suivantes ; celles déjà vécues (« J'y suis ») ne bougent pas. Un changement de jour ne concerne que celle-ci.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("Répéter", selection: $frequency) {
                Text("Jamais").tag(Recurrence.Frequency?.none)
                Text("Chaque jour").tag(Recurrence.Frequency?.some(.daily))
                Text("Chaque semaine").tag(Recurrence.Frequency?.some(.weekly))
                Text("Chaque mois").tag(Recurrence.Frequency?.some(.monthly))
                Text("Chaque année").tag(Recurrence.Frequency?.some(.yearly))
            }
            if let f = frequency {
                Stepper(value: $interval, in: 1...30) {
                    Text(Self.intervalText(f, interval))
                }
                if f == .weekly {
                    HStack(spacing: 4) {
                        ForEach(Self.weekdayOrder, id: \.id) { d in
                            Toggle(d.letter, isOn: Binding(
                                get: { weekdays.contains(d.id) },
                                set: { on in if on { weekdays.insert(d.id) } else if weekdays.count > 1 { weekdays.remove(d.id) } }))
                                .toggleStyle(.button)
                        }
                    }
                }
                Toggle("Jusqu'au", isOn: $hasUntil)
                if hasUntil { DatePicker("", selection: $until, displayedComponents: .date).labelsHidden() }
            }
        }
    }

    static func intervalText(_ f: Recurrence.Frequency, _ n: Int) -> String {
        switch f {
        case .daily: return n == 1 ? "Tous les jours" : "Tous les \(n) jours"
        case .weekly: return n == 1 ? "Toutes les semaines" : "Toutes les \(n) semaines"
        case .monthly: return n == 1 ? "Tous les mois" : "Tous les \(n) mois"
        case .yearly: return n == 1 ? "Tous les ans" : "Tous les \(n) ans"
        }
    }

    static func summary(_ r: Recurrence) -> String {
        let unit: String
        switch r.frequency {
        case .daily: unit = r.interval == 1 ? "jour" : "\(r.interval) jours"
        case .weekly: unit = r.interval == 1 ? "semaine" : "\(r.interval) semaines"
        case .monthly: unit = r.interval == 1 ? "mois" : "\(r.interval) mois"
        case .yearly: unit = r.interval == 1 ? "an" : "\(r.interval) ans"
        }
        var text = "Chaque \(unit)"
        if r.frequency == .weekly, !r.weekdays.isEmpty {
            let names = Calendar.current.shortWeekdaySymbols
            let order = [2, 3, 4, 5, 6, 7, 1].filter { r.weekdays.contains($0) }
            text += " (" + order.map { names[$0 - 1] }.joined(separator: ", ") + ")"
        }
        if let u = r.until { text += ", jusqu'au \(u.formatted(date: .abbreviated, time: .omitted))" }
        return text
    }

    // MARK: Actions

    @ViewBuilder private var deleteControl: some View {
        if !target.isNew {
            if entry.seriesID != nil {
                Menu("Supprimer") {
                    Button("Cette occurrence seulement", role: .destructive) { model.delete(entry.id); dismiss() }
                    Button("Celle-ci et les suivantes", role: .destructive) { model.deleteFollowing(target.entry); dismiss() }
                }
                .fixedSize()
            } else {
                Button("Supprimer", role: .destructive) { model.delete(entry.id); dismiss() }
            }
        }
    }

    private func save() {
        var e = entry
        e.title = e.title.trimmingCharacters(in: .whitespaces)
        e.end = (planned || hasEnd) ? end : nil
        var rule: Recurrence?
        if planned, e.seriesID == nil, let f = frequency {
            rule = Recurrence(frequency: f, interval: interval,
                              weekdays: f == .weekly ? weekdays.sorted() : [],
                              until: hasUntil ? Calendar.current.startOfDay(for: until) : nil)
        }
        if planned, !target.isNew, e.seriesID != nil, scope == .following {
            model.saveSeries(edited: e, original: target.entry)
        } else {
            model.save(e, recurrence: rule)
        }
        dismiss()
    }
}
