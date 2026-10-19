import Foundation

/// One JSON file, written atomically. `~/Library/Application Support/Due/assignments.json`.
public struct JSONStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Honors `DUE_DATA_PATH` (used by previews and tests) before falling back to Application Support.
    /// Built from the real home directory so the sandboxed widget resolves the same file as the app
    /// (inside a sandbox, Application Support and the home directory point into the container).
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = JSONStore.userHomeDirectory()
    ) -> URL {
        if let override = environment["DUE_DATA_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home
            .appendingPathComponent("Library/Application Support/Due", isDirectory: true)
            .appendingPathComponent("assignments.json")
    }

    /// The user's actual home directory, even from inside an app sandbox.
    public static func userHomeDirectory() -> URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Missing file = empty data. A corrupt file throws so the caller can surface it instead of silently wiping.
    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let bytes = try Data(contentsOf: url)
        return try Self.decoder.decode(AppData.self, from: bytes)
    }

    /// The file's contents if another writer (the desktop widget) changed it since `current` was
    /// saved; nil when it still holds exactly `current`, or is missing. Corrupt files throw.
    public func loadIfChanged(comparedTo current: AppData) throws -> AppData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        if bytes == (try? Self.encoder.encode(current)) { return nil }
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
