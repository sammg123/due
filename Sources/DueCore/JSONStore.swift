import Foundation

/// One JSON file, written atomically. `~/Library/Application Support/Due/assignments.json`.
public struct JSONStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Honors `DUE_DATA_PATH` (used by previews and tests) before falling back to Application Support.
    public static func defaultURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["DUE_DATA_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Due", isDirectory: true).appendingPathComponent("assignments.json")
    }

    /// Missing file = empty data. A corrupt file throws so the caller can surface it instead of silently wiping.
    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let bytes = try Data(contentsOf: url)
        return try Self.decoder.decode(AppData.self, from: bytes)
    }

    public func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try Self.encoder.encode(data)
        try bytes.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
