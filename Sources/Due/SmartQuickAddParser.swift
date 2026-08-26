import Foundation
import DueCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// `.unavailable` means the caller should already have checked `SmartQuickAddParser.isAvailable`
/// before calling; `.timedOut` means the model took longer than the UI is willing to wait.
enum SmartParseError: Error {
    case unavailable
    case timedOut
}

/// Wraps Apple's on-device language model (FoundationModels, macOS 26) to turn quick-add text
/// into a `SmartParseResult`. Usable at Due's macOS 14 deployment target; everything
/// FoundationModels-specific lives behind `#if canImport` + `if #available`.
@MainActor
final class SmartQuickAddParser {
    /// Really a `LanguageModelSession` (macOS 26+), type-erased so this compiles at macOS 14.
    /// Reused across calls so the model doesn't re-warm on every keystroke.
    private var session: AnyObject?

    init() {}

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return "Needs macOS 26" }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is not enabled"
        case .unavailable(.modelNotReady): return "Apple Intelligence model is still downloading"
        case .unavailable: return "Apple Intelligence is unavailable"
        }
        #else
        return "Needs macOS 26"
        #endif
    }

    /// Parses `text` on-device. Races the model against a 4 second timeout so a stuck call never
    /// blocks the UI; timing out throws `SmartParseError.timedOut`.
    func parse(_ text: String, now: Date, knownCourses: [String]) async throws -> SmartParseResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { throw SmartParseError.unavailable }
        return try await withTimeout(seconds: 4) { [self] in
            try await runModel(text, now: now, knownCourses: knownCourses)
        }
        #else
        throw SmartParseError.unavailable
        #endif
    }
}

/// Races `operation` against a timeout. Whichever finishes first wins; the loser is abandoned.
private func withTimeout<T: Sendable>(
    seconds: Double, operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SmartParseError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw SmartParseError.timedOut }
        return result
    }
}

#if canImport(FoundationModels)

@available(macOS 26, *)
@Generable
struct GenerableQuickAdd {
    @Guide(description: "The assignment with every date, time, course and duration word removed, kept as close to the user's original wording as possible.")
    var title: String

    @Guide(description: "Due date as YYYY-MM-DD if the text mentions one, else empty.")
    var dueDate: String

    @Guide(description: "Due time as HH:MM in 24-hour time if the text mentions one, else empty.")
    var dueTime: String

    @Guide(description: "Course name if mentioned, matching one of the known courses listed in the prompt when possible, else empty.")
    var course: String

    @Guide(description: "Minutes of work if a duration is mentioned, else 0.", .range(0...1440))
    var estimateMinutes: Int
}

@available(macOS 26, *)
extension SmartQuickAddParser {
    // Fixed rules only; current date/time and known courses vary per call and travel in the
    // per-call prompt instead, since `Instructions` can't change after a session is created.
    // The "count day by day" framing and worked examples below are measured to matter: a plain
    // restatement of the rules produced wrong weekdays and invented fields the text never
    // mentioned. "end of week" still lands on the wrong weekday intermittently even with a
    // matching worked example: a measured on-device model limitation, not a wording gap.
    private static let instructions = Instructions("""
        You extract structured assignment info from a short quick-add phrase for a student's \
        to-do app. Each request states the current date, weekday, and time, and a known course \
        list. Work out any date by counting days one at a time from the given weekday before \
        answering; do not guess or pattern-match a date.

        Rules:
        - "tomorrow" is the next calendar day; "tonight"/"today" are the current day; "this \
        weekend" is the coming Saturday.
        - "end of week"/"eow" is the nearest upcoming Friday: count forward day by day from the \
        given weekday to Friday (0-6 days; today counts as 0 if today is already Friday).
        - "next <weekday>" is that weekday in the FOLLOWING calendar week: count forward to the \
        nearest upcoming occurrence of it (0-6 days), then add exactly 7 more days.
        - A bare four-digit time with no colon or am/pm, like "at 1230", is 24-hour HHmm read \
        directly: hour is the first two digits, minute the last two. "at 1230" is 12:30 PM, not \
        2:30 PM.
        - A course mention, loose ("for writing") or tagged ("#CS225"), maps onto a known \
        course when it clearly refers to one; otherwise leave it as typed, or empty. The known \
        course list is reference only: never assign a course the text doesn't mention or imply.
        - Only fill dueDate, dueTime, course, and estimateMinutes when the text implies them; \
        leave them empty (0 for estimateMinutes) otherwise. Never invent a value the text \
        doesn't support.
        - title always has every date, time, course, and duration word removed, however the \
        rest of the text reads.

        Worked example (current weekday Wednesday): "next fri" is 2 days to this week's \
        Friday, +7 more = 9 days forward. "eow" the same Wednesday is just the +2 days, no \
        extra week.

        Field examples: "pset 4 next fri 5pm #CSCI113 ~2h" -> title "pset 4", dueTime "17:00", \
        course "CSCI113", estimateMinutes 120. "read chapter 3 by end of week" -> title "read \
        chapter 3", dueTime empty, course empty, estimateMinutes 0. No course or duration is \
        mentioned, so both stay empty/0 even though a course list was given.
        """)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        return f
    }()

    /// Tries the reused session first; recreates and retries once on any failure.
    fileprivate func runModel(_ text: String, now: Date, knownCourses: [String]) async throws -> SmartParseResult {
        let prompt = Self.prompt(for: text, now: now, knownCourses: knownCourses)
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 220)
        do {
            let response = try await currentSession().respond(to: prompt, generating: GenerableQuickAdd.self, options: options)
            return Self.resolve(response.content, knownCourses: knownCourses)
        } catch {
            NSLog("Due: smart parse failed, retrying on a fresh session: \(error.localizedDescription)")
            let fresh = LanguageModelSession(instructions: Self.instructions)
            session = fresh
            let response = try await fresh.respond(to: prompt, generating: GenerableQuickAdd.self, options: options)
            return Self.resolve(response.content, knownCourses: knownCourses)
        }
    }

    private func currentSession() -> LanguageModelSession {
        if let existing = session as? LanguageModelSession { return existing }
        let fresh = LanguageModelSession(instructions: Self.instructions)
        session = fresh
        return fresh
    }

    private static func prompt(for text: String, now: Date, knownCourses: [String]) -> String {
        let courseList = knownCourses.isEmpty ? "none" : knownCourses.joined(separator: ", ")
        return """
            Current date and time: \(dateFormatter.string(from: now)).
            Known courses: \(courseList).

            Parse this assignment: "\(text)"
            """
    }

    private static func resolve(_ generated: GenerableQuickAdd, knownCourses: [String]) -> SmartParseResult {
        SmartParseResult(
            title: generated.title,
            dateString: generated.dueDate,
            timeString: generated.dueTime,
            course: generated.course,
            estimateMinutes: generated.estimateMinutes,
            knownCourses: knownCourses
        )
    }
}

#endif
