import SwiftUI
import SillageCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
        } detail: {
            TimelineView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.shift(days: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Jour précédent")
                Button("Aujourd'hui") { model.day = Date() }.disabled(model.isToday)
                Button { model.shift(days: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Jour suivant")
            }
            ToolbarItemGroup {
                DatePicker("", selection: $model.day, displayedComponents: .date).labelsHidden()
                Menu {
                    Button("Rendez-vous prévu…") { model.editor = model.newPlanned() }
                    Button("Activité passée…") { model.editor = model.newPast() }
                } label: { Label("Ajouter", systemImage: "plus") }
            }
        }
        .navigationTitle(model.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized)
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
