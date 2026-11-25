import Foundation

/// Stockage local : un fichier JSON dans ~/Library/Application Support/Sillage.
public struct Store {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var `default`: Store {
        // SILLAGE_DATA : fichier alternatif (tests, captures d'écran de la documentation).
        if let path = ProcessInfo.processInfo.environment["SILLAGE_DATA"] { return Store(url: URL(fileURLWithPath: path)) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Store(url: base.appendingPathComponent("Sillage/data.json"))
    }

    private struct File: Codable { var entries: [Entry]; var series: [Series]? }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public struct LoadResult: Equatable {
        public var entries: [Entry]
        public var series: [Series] = []
        /// Si le fichier était illisible : l'endroit où il a été mis de côté (il n'est jamais écrasé).
        public var quarantinedAt: URL?
    }

    /// Lit les données. Un fichier absent donne une liste vide ; un fichier illisible est mis de côté
    /// (`data.corrompu-<date>.json`) au lieu d'être écrasé par la prochaine sauvegarde.
    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: url) else { return LoadResult(entries: [], quarantinedAt: nil) }
        if let file = try? Self.decoder.decode(File.self, from: data) {
            return LoadResult(entries: file.entries, series: file.series ?? [], quarantinedAt: nil)
        }
        let stamp = Self.stamp(Date(), format: "yyyy-MM-dd-HHmmss")
        let aside = url.deletingLastPathComponent().appendingPathComponent("data.corrompu-\(stamp).json")
        do { try FileManager.default.moveItem(at: url, to: aside) } catch {
            try? data.write(to: aside)
            try? FileManager.default.removeItem(at: url)
        }
        return LoadResult(entries: [], quarantinedAt: aside)
    }

    /// Écriture atomique (un plantage en cours d'écriture ne corrompt pas le fichier),
    /// précédée d'une sauvegarde quotidienne.
    public func save(_ entries: [Entry], series: [Series] = []) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        backupIfNeeded()
        try Self.encoder.encode(File(entries: entries, series: series)).write(to: url, options: .atomic)
    }

    public var backupsDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("Sauvegardes") }

    /// Une copie par jour dans `Sauvegardes/`, les 14 plus récentes sont conservées.
    func backupIfNeeded(now: Date = Date(), keep: Int = 14) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let dir = backupsDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("data-\(Self.stamp(now, format: "yyyy-MM-dd")).json")
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: url, to: target) }
        let all = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("data-") }.sorted()
        for old in all.dropLast(keep) { try? fm.removeItem(at: dir.appendingPathComponent(old)) }
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
}
