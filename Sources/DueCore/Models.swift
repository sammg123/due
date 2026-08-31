import Foundation

/// Fixed palette so colors stay consistent between the course tag, settings, and persistence.
public enum PaletteColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    /// Colors handed out to new courses, in order. Excludes the urgency colors (red/orange/yellow)
    /// so a course tag never reads as an urgency signal.
    public static let courseRotation: [PaletteColor] = [.blue, .purple, .teal, .pink, .indigo, .green, .cyan, .mint, .brown]
}

public struct Assignment: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var course: String?
    public var dueDate: Date
    public var estimateMinutes: Int?
    public var notes: String?
    public var isDone: Bool
    public var completedAt: Date?
    public var createdAt: Date
    /// Manual position within a bucket. Lower sorts first.
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        title: String,
        course: String? = nil,
        dueDate: Date,
        estimateMinutes: Int? = nil,
        notes: String? = nil,
        isDone: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.course = course
        self.dueDate = dueDate
        self.estimateMinutes = estimateMinutes
        self.notes = notes
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    /// Returns a copy with done state flipped. Never mutates.
    public func togglingDone(at date: Date = Date()) -> Assignment {
        var copy = self
        copy.isDone = !isDone
        copy.completedAt = copy.isDone ? date : nil
        return copy
    }

    public func withSortOrder(_ order: Int) -> Assignment {
        var copy = self
        copy.sortOrder = order
        return copy
    }

    /// Tolerant decoding: any field added later is optional on read.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        course = try c.decodeIfPresent(String.self, forKey: .course)
        dueDate = try c.decode(Date.self, forKey: .dueDate)
        estimateMinutes = try c.decodeIfPresent(Int.self, forKey: .estimateMinutes)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

public struct DueSettings: Codable, Equatable, Sendable {
    /// Due within this many days (after today) = "Soon" (yellow).
    public var soonDays: Int
    /// Due within this many days = "This week" (blue). Beyond = "Later" (gray).
    public var weekDays: Int
    public var launchAtLogin: Bool
    /// Use the on-device language model (Apple Intelligence) to parse quick-add text when available.
    public var smartParsing: Bool
    /// Keep the .m4a of each lecture recording alongside the notes (transcription happens either way).
    public var saveLectureAudio: Bool
    /// Which model runs the notes AI actions: "auto" (best local Ollama model, else Apple
    /// Intelligence), "apple", or an Ollama model name. Everything runs on this Mac.
    public var notesAIModel: String

    public static let defaultSoonDays = 3
    public static let defaultWeekDays = 7
    public static let autoAIModel = "auto"
    public static let appleAIModel = "apple"

    public init(soonDays: Int = DueSettings.defaultSoonDays, weekDays: Int = DueSettings.defaultWeekDays, launchAtLogin: Bool = false, smartParsing: Bool = true, saveLectureAudio: Bool = true, notesAIModel: String = DueSettings.autoAIModel) {
        self.soonDays = soonDays
        self.weekDays = weekDays
        self.launchAtLogin = launchAtLogin
        self.smartParsing = smartParsing
        self.saveLectureAudio = saveLectureAudio
        self.notesAIModel = notesAIModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soonDays = try c.decodeIfPresent(Int.self, forKey: .soonDays) ?? DueSettings.defaultSoonDays
        weekDays = try c.decodeIfPresent(Int.self, forKey: .weekDays) ?? DueSettings.defaultWeekDays
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        smartParsing = try c.decodeIfPresent(Bool.self, forKey: .smartParsing) ?? true
        saveLectureAudio = try c.decodeIfPresent(Bool.self, forKey: .saveLectureAudio) ?? true
        notesAIModel = try c.decodeIfPresent(String.self, forKey: .notesAIModel) ?? DueSettings.autoAIModel
    }
}

/// Everything that gets persisted, as one value.
public struct AppData: Codable, Equatable, Sendable {
    public var assignments: [Assignment]
    public var courseColors: [String: PaletteColor]
    public var settings: DueSettings

    public static let empty = AppData(assignments: [], courseColors: [:], settings: DueSettings())

    public init(assignments: [Assignment], courseColors: [String: PaletteColor], settings: DueSettings) {
        self.assignments = assignments
        self.courseColors = courseColors
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        courseColors = try c.decodeIfPresent([String: PaletteColor].self, forKey: .courseColors) ?? [:]
        settings = try c.decodeIfPresent(DueSettings.self, forKey: .settings) ?? DueSettings()
    }
}
