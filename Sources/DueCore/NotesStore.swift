import Foundation

/// One JSON file per note under `~/Library/Application Support/Due/Notes/`, written atomically.
/// Per-note files keep autosave cheap: a keystroke rewrites one small file, not every note.
/// Recordings live beside them in `Notes/Audio/`.
public struct NotesStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public var audioDirectory: URL { directory.appendingPathComponent("Audio", isDirectory: true) }
    public var drawingsDirectory: URL { directory.appendingPathComponent("Drawings", isDirectory: true) }

    /// Honors `DUE_NOTES_PATH` (used by previews and tests) before falling back to Application Support.
    public static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["DUE_NOTES_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Due", isDirectory: true).appendingPathComponent("Notes", isDirectory: true)
    }

    public struct LoadResult: Equatable, Sendable {
        public let notes: [Note]
        /// JSON files that would not decode. Left on disk, never silently deleted.
        public let skippedFiles: [String]
    }

    /// Missing directory = no notes. A corrupt note file is skipped and reported, the rest load.
    public func loadAll() throws -> LoadResult {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return LoadResult(notes: [], skippedFiles: [])
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var notes: [Note] = []
        var skipped: [String] = []
        for file in files where file.pathExtension == "json" {
            do {
                let bytes = try Data(contentsOf: file)
                notes.append(try Self.decoder.decode(Note.self, from: bytes))
            } catch {
                skipped.append(file.lastPathComponent)
            }
        }
        return LoadResult(notes: notes, skippedFiles: skipped.sorted())
    }

    public func save(_ note: Note) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = try Self.encoder.encode(note)
        try bytes.write(to: url(for: note.id), options: .atomic)
    }

    /// Removes the note file and any recordings and drawings it listed.
    public func delete(_ id: UUID) throws {
        let noteURL = url(for: id)
        if let bytes = try? Data(contentsOf: noteURL),
           let note = try? Self.decoder.decode(Note.self, from: bytes) {
            for fileName in note.audioFiles where Self.isSafeRelativeFileName(fileName) {
                try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(fileName))
            }
            for fileName in note.drawingFiles where Self.isSafeRelativeFileName(fileName) {
                try? FileManager.default.removeItem(at: drawingsDirectory.appendingPathComponent(fileName))
            }
        }
        guard FileManager.default.fileExists(atPath: noteURL.path) else { return }
        try FileManager.default.removeItem(at: noteURL)
    }

    // MARK: - Drawings

    public static func drawingFileName(for id: UUID) -> String { "\(id.uuidString).json" }

    public func loadDrawing(id: UUID) throws -> Drawing {
        let bytes = try Data(contentsOf: drawingsDirectory.appendingPathComponent(Self.drawingFileName(for: id)))
        return try Self.decoder.decode(Drawing.self, from: bytes)
    }

    public func saveDrawing(_ drawing: Drawing) throws {
        try FileManager.default.createDirectory(at: drawingsDirectory, withIntermediateDirectories: true)
        let bytes = try Self.encoder.encode(drawing)
        try bytes.write(to: drawingsDirectory.appendingPathComponent(Self.drawingFileName(for: drawing.id)), options: .atomic)
    }

    public func deleteDrawing(id: UUID) throws {
        let url = drawingsDirectory.appendingPathComponent(Self.drawingFileName(for: id))
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Audio file names come back off disk; a tampered note file must not be able to point a
    /// delete or an open outside the Audio directory.
    public static func isSafeRelativeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".."
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
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
