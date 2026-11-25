import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    /// L'app reste active dans la barre de menus quand la fenêtre est fermée.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct SillageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    private func performUndo(redo: Bool) {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(Selector(redo ? "redo:" : "undo:"), to: nil, from: nil)
        } else if redo {
            model.redo()
        } else {
            model.undo()
        }
    }

    var body: some Scene {
        // Une seule fenêtre : « Ouvrir Sillage » (barre de menus) la ramène au premier plan au lieu d'en créer une autre.
        Window("Sillage", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouveau rendez-vous…") { model.editor = model.newPlanned() }
                    .keyboardShortcut("n")
                Button("Ajouter une activité passée…") { model.editor = model.newPast() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                // Dans un champ de texte, ⌘Z annule la frappe ; ailleurs, il annule la dernière modification de Sillage.
                Button("Annuler") { performUndo(redo: false) }.keyboardShortcut("z")
                Button("Rétablir") { performUndo(redo: true) }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Journée") {
                Button("Période précédente") { model.navigate(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Période suivante") { model.navigate(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Aujourd'hui") { model.day = Date() }.keyboardShortcut("t")
                Divider()
                Button("Vue Jour") { model.viewMode = .day }.keyboardShortcut("1")
                Button("Vue Semaine") { model.viewMode = .week }.keyboardShortcut("2")
                Button("Vue Mois") { model.viewMode = .month }.keyboardShortcut("3")
                Button("Vue Tâches") { model.viewMode = .tasks }.keyboardShortcut("4")
                Button("Vue Récap") { model.viewMode = .recap }.keyboardShortcut("5")
            }
        }
        MenuBarExtra {
            MenuBarPanel().environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
