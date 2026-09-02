import Foundation

/// One note. Body is plain text (with lightweight markdown headings from lecture capture).
public struct Note: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var course: String?
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Total seconds of lecture audio captured into this note, across all recordings.
    public var lectureSeconds: Int
    /// Saved recordings, as file names relative to the store's Audio directory.
    public var audioFiles: [String]
    /// Attached drawings, as file names relative to the store's Drawings directory.
    /// Placement in the note comes from `[drawing: <id>]` lines in the body.
    public var drawingFiles: [String]

    public static let displayTitleMaxLength = 60

    public init(
        id: UUID = UUID(),
        title: String,
        course: String? = nil,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lectureSeconds: Int = 0,
        audioFiles: [String] = [],
        drawingFiles: [String] = []
    ) {
        self.id = id
        self.title = title
        self.course = course
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lectureSeconds = lectureSeconds
        self.audioFiles = audioFiles
        self.drawingFiles = drawingFiles
    }

    /// The title, or the first non-empty body line, or "Untitled".
    public var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        guard let line = firstNonEmptyBodyLine else { return "Untitled" }
        if line.count <= Self.displayTitleMaxLength { return line }
        return String(line.prefix(Self.displayTitleMaxLength - 1)) + "…"
    }

    /// One-line body excerpt for list rows: markdown markers stripped, whitespace collapsed.
    /// When the display title came from the body, that line is skipped so the preview
    /// doesn't repeat it.
    public var preview: String {
        var lines = body.components(separatedBy: .newlines)
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            lines.removeSubrange(...first)
        }
        let collapsed = lines.map(Self.strippingMarkdownMarkers)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(160))
    }

    /// Drops structural markers (`#` headings, `-` bullets, `>` callouts, `**`/`` ` `` inline,
    /// divider and table-separator lines); the text itself is kept.
    private static func strippingMarkdownMarkers(_ line: String) -> String {
        var trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
        // Divider / table-separator lines carry no preview-worthy text at all.
        if !trimmed.isEmpty, trimmed.allSatisfy({ "-|: ".contains($0) }) { return "" }
        if trimmed.lowercased().hasPrefix("[drawing:") { return "" }
        while trimmed.first == "#" { trimmed = trimmed.dropFirst() }
        if trimmed.first == "-" || trimmed.first == ">" { trimmed = trimmed.dropFirst() }
        return String(trimmed)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "|", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    public var wordCount: Int {
        body.split(whereSeparator: \.isWhitespace).count
    }

    private var firstNonEmptyBodyLine: String? {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    // MARK: - Immutable updates

    public func updating(body: String, at date: Date = Date()) -> Note {
        var copy = self
        copy.body = body
        copy.updatedAt = date
        return copy
    }

    public func updating(title: String, at date: Date = Date()) -> Note {
        var copy = self
        copy.title = title
        copy.updatedAt = date
        return copy
    }

    public func updating(course: String?, at date: Date = Date()) -> Note {
        var copy = self
        copy.course = course
        copy.updatedAt = date
        return copy
    }

    public func updating(addingAudioFile fileName: String, seconds: Int, at date: Date = Date()) -> Note {
        var copy = self
        copy.audioFiles = audioFiles + [fileName]
        copy.lectureSeconds = lectureSeconds + seconds
        copy.updatedAt = date
        return copy
    }

    public func updating(addingDrawingFile fileName: String, at date: Date = Date()) -> Note {
        var copy = self
        copy.drawingFiles = drawingFiles + [fileName]
        copy.updatedAt = date
        return copy
    }

    public func updating(removingDrawingFile fileName: String, at date: Date = Date()) -> Note {
        var copy = self
        copy.drawingFiles = drawingFiles.filter { $0 != fileName }
        copy.updatedAt = date
        return copy
    }

    /// Tolerant decoding: any field added later is optional on read.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        course = try c.decodeIfPresent(String.self, forKey: .course)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lectureSeconds = try c.decodeIfPresent(Int.self, forKey: .lectureSeconds) ?? 0
        audioFiles = try c.decodeIfPresent([String].self, forKey: .audioFiles) ?? []
        drawingFiles = try c.decodeIfPresent([String].self, forKey: .drawingFiles) ?? []
    }
}
