import SwiftUI
import SillageCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showCalendar = false

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
                .sheet(isPresented: $model.showBackup) { BackupSheet() }
        } detail: {
            switch model.viewMode {
            case .day: TimelineView()
            case .week: WeekView()
            case .month: MonthView()
            case .tasks: TasksView()
            case .recap: RecapView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Période précédente (⌘←)")
                Button("Aujourd'hui") { model.day = Date() }.disabled(model.isCurrentPeriod)
                Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }
                    .help("Période suivante (⌘→)")
            }
            ToolbarItemGroup {
                Picker("Vue", selection: $model.viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Jour (⌘1) · Semaine (⌘2) · Mois (⌘3)")
                Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }
                    .help("Aller à une date")
                    .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                        DatePicker("", selection: $model.day, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden().padding(12)
                    }
                Menu {
                    Button("Rendez-vous prévu…") { model.editor = model.newPlanned() }
                    Button("Activité passée…") { model.editor = model.newPast() }
                } label: { Label("Ajouter", systemImage: "plus") }
            }
        }
        .navigationTitle(model.periodTitle)
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .sheet(item: $model.editor) { target in
            EditorSheet(target: target)
        }
        .alert("Données illisibles", isPresented: Binding(get: { model.loadWarning != nil },
                                                           set: { if !$0 { model.loadWarning = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.loadWarning ?? "") }
        .alert("Enregistrement impossible", isPresented: Binding(get: { model.saveError != nil },
                                                                  set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.saveError ?? "") }
    }
}
