import SwiftUI
import AppKit
import SillageCore

/// Fenêtre « Calendriers Mac et Google » : afficher ses rendez-vous existants dans la colonne « Prévu » (optionnel, lecture seule).
struct CalendarsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    private var source: CalendarSource { model.calendars }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 22)).foregroundStyle(Theme.accent)
                Text("Calendriers Mac et Google").font(Theme.rounded(22, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            introCard
            if source.enabled && source.access == .granted { listCard }
            googleCard
        }
        .padding(22)
        .frame(width: 580)
        .background(Theme.background)
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }

    // MARK: Cartes

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rendez-vous de vos calendriers").sectionLabel()
            Text("Affichez les événements de l'app Calendrier de votre Mac (iCloud, Google, Exchange…) dans la colonne « Prévu », à côté de vos propres rendez-vous. C'est **facultatif** et en **lecture seule** : Sillage n'écrit rien dans vos calendriers et ne copie rien dans ses données. Vous pouvez utiliser « J'y suis » sur ces rendez-vous comme sur les autres.")
                .font(Theme.rounded(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(get: { source.enabled && source.access == .granted }, set: { on in
                if on { busy = true; Task { await source.enable(); busy = false } } else { source.disable() }
            })) {
                Text("Afficher mes calendriers").font(Theme.rounded(14, .semibold))
            }
            .toggleStyle(.switch).disabled(busy)

            switch source.access {
            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    Label("L'accès aux calendriers est refusé pour Sillage. Autorisez-le dans Réglages Système → Confidentialité et sécurité → Calendriers, puis réactivez l'option.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir les réglages de confidentialité") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }.buttonStyle(ChipButtonStyle(category: "Autre"))
                }
            case .notDetermined:
                Text("macOS vous demandera l'autorisation au moment de l'activation.")
                    .font(Theme.rounded(12)).foregroundStyle(Theme.muted)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendriers affichés").sectionLabel()
            if source.calendars.isEmpty {
                Text("Aucun calendrier trouvé sur ce Mac.").font(Theme.rounded(13)).foregroundStyle(Theme.muted)
            }
            ForEach(Dictionary(grouping: source.calendars, by: \.account).keys.sorted(), id: \.self) { account in
                VStack(alignment: .leading, spacing: 6) {
                    if !account.isEmpty { Text(account).font(Theme.rounded(11, .bold)).foregroundStyle(Theme.muted) }
                    ForEach(source.calendars.filter { $0.account == account }) { c in
                        Toggle(isOn: Binding(get: { source.isSelected(c.id) }, set: { source.setSelected(c.id, $0) })) {
                            HStack(spacing: 8) {
                                Circle().fill(c.color).frame(width: 10, height: 10)
                                Text(c.title).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.ink)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Divider()
            Toggle(isOn: Binding(get: { source.showAllDay }, set: { source.setShowAllDay($0) })) {
                Text("Afficher aussi les événements « toute la journée »").font(Theme.rounded(13))
            }
            .toggleStyle(.checkbox)
            Text("Les événements refusés ou annulés ne sont pas affichés.").font(Theme.rounded(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var googleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Et Google ?").sectionLabel()
            Text("Sillage lit ce que l'app Calendrier de votre Mac affiche. Pour y voir un agenda Google : Réglages Système → Comptes Internet → Google, en laissant cochée l'option **Calendriers**. Il apparaîtra ensuite dans la liste ci-dessus.")
                .font(Theme.rounded(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Button("Ouvrir Comptes Internet") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
            }.buttonStyle(ChipButtonStyle(category: "Autre"))
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
