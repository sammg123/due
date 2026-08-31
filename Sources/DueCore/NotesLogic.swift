import Foundation

public enum NoteSort: String, CaseIterable, Codable, Sendable {
    case dateEdited
    case name
    case course

    public var label: String {
        switch self {
        case .dateEdited: return "Date edited"
        case .name: return "Name"
        case .course: return "Class"
        }
    }
}

public struct NoteCourseGroup: Identifiable, Equatable, Sendable {
    public let course: String?
    public let notes: [Note]
    public var id: String { course ?? "\u{FFFF}no-course" }

    public init(course: String?, notes: [Note]) {
        self.course = course
        self.notes = notes
    }
}

/// Pure sorting/filtering/grouping for the notes browser.
public enum NotesLogic {
    /// Sorts past any course so no-course notes land last, matching AppState's course sorts.
    private static let noCourse = "\u{FFFF}"

    public static func sort(_ notes: [Note], by sort: NoteSort) -> [Note] {
        switch sort {
        case .dateEdited:
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        case .name:
            return notes.sorted {
                let cmp = $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.updatedAt > $1.updatedAt
            }
        case .course:
            return notes.sorted {
                let a = $0.course ?? noCourse, b = $1.course ?? noCourse
                if a != b { return a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    /// Narrows by course (nil = all) and case-insensitive search over title, body, and course.
    public static func filter(_ notes: [Note], course: String?, search: String) -> [Note] {
        var result = notes
        if let course {
            result = result.filter { $0.course == course }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        return result.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || (note.course?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Consecutive course groups (alphabetical, no-course last), newest first within each.
    public static func groupedByCourse(_ notes: [Note]) -> [NoteCourseGroup] {
        let sorted = sort(notes, by: .course)
        var groups: [NoteCourseGroup] = []
        for note in sorted {
            if let last = groups.last, last.course == note.course {
                groups[groups.count - 1] = NoteCourseGroup(course: last.course, notes: last.notes + [note])
            } else {
                groups.append(NoteCourseGroup(course: note.course, notes: [note]))
            }
        }
        return groups
    }
}
