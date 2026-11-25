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
            CommandMenu("Journée") {
                Button("Jour précédent") { model.shift(days: -1) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Jour suivant") { model.shift(days: 1) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Aujourd'hui") { model.day = Date() }.keyboardShortcut("t")
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
