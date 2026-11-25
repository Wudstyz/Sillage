import Foundation

/// Export CSV pour un tableur : séparateur « ; » et BOM UTF-8 (Excel en français lit ainsi les accents).
public enum CSVExport {
    public static let header = ["Type", "Titre", "Catégorie", "Début", "Fin", "Durée (min)", "Durée (h:mm)", "En cours", "Notes"]

    /// Les entrées qui touchent [`from`, `to`) (toutes si les bornes sont absentes), de la plus ancienne à la plus récente.
    /// Les durées sont celles de chaque entrée : le partage du temps entre tâches simultanées n'y est pas appliqué.
    public static func csv(_ entries: [Entry], now: Date, from: Date? = nil, to: Date? = nil,
                           calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"

        let rows = entries
            .filter { e in
                (to.map { e.start < $0 } ?? true) && (from.map { e.effectiveEnd(now: now) > $0 } ?? true)
            }
            .sorted { $0.start < $1.start }
            .map { e -> [String] in
                let end = e.effectiveEnd(now: now)
                let minutes = max(0, Int((end.timeIntervalSince(e.start) / 60).rounded()))
                return [e.kind == .actual ? "Réel" : "Prévu", e.title, e.category, f.string(from: e.start),
                        e.end.map { f.string(from: $0) } ?? "", "\(minutes)",
                        String(format: "%d:%02d", minutes / 60, minutes % 60), e.isRunning ? "oui" : "non", e.trimmedNotes ?? ""]
            }
        return "\u{FEFF}" + ([header] + rows).map { $0.map(escape).joined(separator: ";") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Entoure de guillemets un champ qui contient un séparateur, un guillemet ou un retour à la ligne.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
