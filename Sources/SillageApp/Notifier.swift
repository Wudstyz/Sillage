import Foundation
import UserNotifications
import SillageCore

/// Rappels : notifications locales programmées pour les prochains rendez-vous.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// `nil` hors d'une app empaquetée (ex. exécution directe en développement) : pas de notifications.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Remplace les notifications en attente par les prochains rappels (60 au plus, la limite système est de 64).
    func reschedule(_ entries: [Entry], now: Date) {
        guard let center else { return }
        let upcoming = Reminders.upcoming(entries, now: now)
        center.removeAllPendingNotificationRequests()
        guard !upcoming.isEmpty else { return }
        requestAuthorization()
        for (e, fire) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = e.title
            content.body = Reminders.body(for: e)
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            center.add(UNNotificationRequest(identifier: e.id.uuidString, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    /// Affiche aussi la bannière quand Sillage est au premier plan.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
