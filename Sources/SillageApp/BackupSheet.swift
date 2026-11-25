import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SillageCore

/// Fenêtre « Sauvegarde et export » : tout ce qu'il faut pour ne rien perdre.
struct BackupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: (text: String, ok: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 22)).foregroundStyle(Theme.accent)
                Text("Sauvegarde et export").font(Theme.rounded(22, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            automaticCard
            folderCard
            exportCard
            restoreCard

            if let message {
                Label(message.text, systemImage: message.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(message.ok ? Theme.color(for: "Loisirs") : Theme.warning)
            }
        }
        .padding(22)
        .frame(width: 580)
        .background(Theme.background)
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }

    // MARK: Cartes

    private var automaticCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sauvegarde automatique").sectionLabel()
            Text("Vos données sont enregistrées à chaque modification. En plus, une copie de secours est faite toutes les 10 minutes quand quelque chose change (les 48 dernières sont gardées), et une par jour pendant 14 jours. Une dernière copie est faite à la fermeture de l'app.")
                .font(Theme.rounded(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Label(lastBackupText, systemImage: "clock.arrow.circlepath")
                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.muted)
            HStack {
                Button("Sauvegarder maintenant") {
                    model.backupNow()
                    message = ("Copie de secours faite.", true)
                }.buttonStyle(AccentButtonStyle(compact: true))
                Button("Ouvrir le dossier des données") { NSWorkspace.shared.open(model.dataFolder) }
                    .buttonStyle(ChipButtonStyle(category: "Autre"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copie dans un dossier de votre choix").sectionLabel()
            if let path = model.backupFolder {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text((path as NSString).abbreviatingWithTildeInPath).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let note = model.backupFolderNote {
                    Text(note).font(Theme.rounded(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Changer de dossier…", action: chooseFolder).buttonStyle(ChipButtonStyle(category: "Autre"))
                    Button("Arrêter") { model.clearBackupFolder() }.buttonStyle(ChipButtonStyle(category: "Santé"))
                }
            } else {
                Text("Ajoutez une copie dans iCloud Drive ou sur un disque externe : une sauvegarde par jour (30 jours gardés), mise à jour automatiquement. Si le disque n'est pas branché, la copie reprend dès qu'il l'est.")
                    .font(Theme.rounded(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Button("Choisir un dossier…", action: chooseFolder).buttonStyle(AccentButtonStyle(compact: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exporter").sectionLabel()
            HStack {
                Button { exportFull() } label: { Label("Complète (.json)…", systemImage: "square.and.arrow.up").lineLimit(1) }
                    .buttonStyle(ChipButtonStyle(category: "Loisirs")).fixedSize()
                Button { exportCSV(periodOnly: false) } label: { Label("CSV · tout…", systemImage: "tablecells").lineLimit(1) }
                    .buttonStyle(ChipButtonStyle(category: "Travail")).fixedSize()
                    .help("Tout l'historique")
                Button { exportCSV(periodOnly: true) } label: { Label("CSV · cette période…", systemImage: "tablecells").lineLimit(1) }
                    .buttonStyle(ChipButtonStyle(category: "Travail")).fixedSize()
                    .help("La période de la vue en cours : \(model.periodTitle)")
            }
            Text("La sauvegarde complète (.json) contient tout et peut être restaurée. Le CSV s'ouvre dans Excel ou Numbers ; les durées sont celles de chaque entrée, sans le partage du temps entre tâches simultanées.")
                .font(Theme.rounded(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Restaurer").sectionLabel()
            HStack {
                Button { restore() } label: { Label("Restaurer depuis un fichier…", systemImage: "arrow.uturn.backward.circle") }
                    .buttonStyle(ChipButtonStyle(category: "Santé"))
            }
            Text("Remplace vos données actuelles par celles du fichier choisi (une sauvegarde complète ou l'une des copies automatiques). L'état actuel est gardé avant, et ⌘Z annule la restauration.")
                .font(Theme.rounded(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var lastBackupText: String {
        guard let d = model.lastBackup else { return "Aucune copie de secours pour l'instant" }
        let time = d.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(d)
            ? "Dernière copie de secours : aujourd'hui à \(time)"
            : "Dernière copie de secours : \(d.formatted(date: .abbreviated, time: .omitted)) à \(time)"
    }

    // MARK: Actions (panneaux macOS)

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier où copier chaque jour une sauvegarde de vos données"
        if panel.runModal() == .OK, let url = panel.url {
            model.setBackupFolder(url)
            message = ("Copie automatique activée dans « \(url.lastPathComponent) ».", true)
        }
    }

    private func save(suggested: String, type: UTType, _ write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(url)
            message = ("Exporté : \(url.lastPathComponent)", true)
        } catch {
            message = ("Échec de l'export : \(error.localizedDescription)", false)
        }
    }

    private var stamp: String { Date().formatted(.iso8601.year().month().day()) }

    private func exportFull() { save(suggested: "Sillage-sauvegarde-\(stamp).json", type: .json) { try model.exportFull(to: $0) } }

    private func exportCSV(periodOnly: Bool) {
        save(suggested: "Sillage-\(periodOnly ? "periode" : "historique")-\(stamp).csv", type: .commaSeparatedText) {
            try model.exportCSV(to: $0, periodOnly: periodOnly)
        }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.fileExists(atPath: model.snapshotsFolder.path) ? model.snapshotsFolder : model.dataFolder
        panel.prompt = "Choisir"
        panel.message = "Choisissez une sauvegarde complète ou une copie automatique (dossier Sauvegardes)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let info = model.backupInfo(at: url) else {
            message = ("Ce fichier n'est pas une sauvegarde Sillage valide : rien n'a été modifié.", false)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Restaurer cette sauvegarde ?"
        alert.informativeText = "Vos données actuelles (\(model.entries.count) entrées) seront remplacées par celles du fichier (\(info.entries) entrées, \(info.series) série(s)). L'état actuel est gardé avant, et ⌘Z annule la restauration."
        alert.addButton(withTitle: "Annuler")          // premier bouton = par défaut : on ne remplace pas par accident
        alert.addButton(withTitle: "Restaurer")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        message = model.restore(from: url)
            ? ("Sauvegarde restaurée (⌘Z pour annuler).", true)
            : ("Restauration impossible : rien n'a été modifié.", false)
    }
}
