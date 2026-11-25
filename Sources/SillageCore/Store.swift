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

    // MARK: Copies de secours continues

    public var snapshotsDirectory: URL { backupsDirectory.appendingPathComponent("Continu") }

    private static let snapshotFormat = "yyyy-MM-dd-HHmmss"

    private func snapshotNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: snapshotsDirectory.path)) ?? [])
            .filter { $0.hasPrefix("data-") && $0.hasSuffix(".json") }.sorted()
    }

    /// Octets du fichier de données s'il est lisible et non vide (on ne sauvegarde jamais un fichier illisible ni vide).
    private func validCurrentData() -> Data? {
        guard let data = try? Data(contentsOf: url), let file = try? Self.decoder.decode(File.self, from: data),
              !(file.entries.isEmpty && (file.series ?? []).isEmpty) else { return nil }
        return data
    }

    /// Date de la dernière copie de secours continue, s'il y en a une.
    public func latestSnapshotDate() -> Date? {
        guard let last = snapshotNames().last else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Self.snapshotFormat
        return f.date(from: String(last.dropFirst(5).dropLast(5)))
    }

    /// Copie de secours « au fil de la journée » : une copie complète du fichier de données dans `Sauvegardes/Continu/`,
    /// au plus une toutes les `minInterval` secondes (sauf `force`), seulement si le contenu a changé, les `keep` dernières
    /// gardées. À appeler après chaque enregistrement : un incident ne coûte alors que quelques minutes.
    /// Renvoie le fichier créé, ou `nil` s'il n'y avait rien à faire.
    @discardableResult
    public func snapshotIfNeeded(now: Date = Date(), minInterval: TimeInterval = 10 * 60, keep: Int = 48,
                                 force: Bool = false) -> URL? {
        guard let data = validCurrentData() else { return nil }
        let fm = FileManager.default
        if let last = snapshotNames().last {
            if let lastData = try? Data(contentsOf: snapshotsDirectory.appendingPathComponent(last)), lastData == data { return nil }
            if !force, let date = latestSnapshotDate(), now.timeIntervalSince(date) < minInterval { return nil }
        }
        try? fm.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        let target = snapshotsDirectory.appendingPathComponent("data-\(Self.stamp(now, format: Self.snapshotFormat)).json")
        guard !fm.fileExists(atPath: target.path), (try? data.write(to: target, options: .atomic)) != nil else { return nil }
        for old in snapshotNames().dropLast(keep) { try? fm.removeItem(at: snapshotsDirectory.appendingPathComponent(old)) }
        return target
    }

    /// Copie le fichier de données dans un dossier choisi par l'utilisateur (iCloud Drive, disque externe…) :
    /// un fichier par jour, `keepDays` jours gardés. Ne crée pas le dossier : s'il est absent (disque débranché), ne fait rien.
    @discardableResult
    public func mirror(to directory: URL, now: Date = Date(), keepDays: Int = 30) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let data = validCurrentData() else { return nil }
        let target = directory.appendingPathComponent("Sillage-sauvegarde-\(Self.stamp(now, format: "yyyy-MM-dd")).json")
        guard (try? data.write(to: target, options: .atomic)) != nil else { return nil }
        let all = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("Sillage-sauvegarde-") && $0.hasSuffix(".json") }.sorted()
        for old in all.dropLast(keepDays) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old)) }
        return target
    }

    // MARK: Export et restauration

    /// Garde une copie brute du fichier de données actuel (même illisible) avant de le remplacer par une restauration.
    @discardableResult
    public func keepCopyBeforeRestore(now: Date = Date()) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let dir = backupsDirectory.appendingPathComponent("Avant-restauration")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("data-\(Self.stamp(now, format: Self.snapshotFormat)).json")
        return (try? fm.copyItem(at: url, to: target)) != nil ? target : nil
    }

    /// Écrit une sauvegarde complète (même format que le fichier de données) à l'endroit voulu.
    public static func export(entries: [Entry], series: [Series], to url: URL) throws {
        try encoder.encode(File(entries: entries, series: series)).write(to: url, options: .atomic)
    }

    /// Lit une sauvegarde : `nil` si le fichier n'est pas une sauvegarde Sillage valide.
    public static func readBackup(at url: URL) -> (entries: [Entry], series: [Series])? {
        guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(File.self, from: data) else { return nil }
        return (file.entries, file.series ?? [])
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
}
