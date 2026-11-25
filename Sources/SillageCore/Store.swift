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

    private struct File: Codable { var entries: [Entry] }

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

    public func load() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder.decode(File.self, from: data))?.entries ?? []
    }

    /// Écriture atomique : un plantage en cours d'écriture ne corrompt pas le fichier.
    public func save(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(File(entries: entries)).write(to: url, options: .atomic)
    }
}
