import Foundation

/// Result of parsing one quick-add line like "pset 4 fri 5pm #CS225 ~2h".
public struct QuickAddParse: Equatable, Sendable {
    public var title: String
    public var dueDate: Date?
    public var course: String?
    public var estimateMinutes: Int?
    /// True when the user typed a clock time (so the UI should not overwrite it with 11:59 PM).
    public var hasExplicitTime: Bool

    public init(title: String, dueDate: Date? = nil, course: String? = nil, estimateMinutes: Int? = nil, hasExplicitTime: Bool = false) {
        self.title = title
        self.dueDate = dueDate
        self.course = course
        self.estimateMinutes = estimateMinutes
        self.hasExplicitTime = hasExplicitTime
    }
}

/// Natural-language quick add. Recognizes:
///   dates: today, tonight, tomorrow/tmr/tmrw, mon..sunday, "next fri", "in 3 days", "in 2 weeks",
///          eod, eow, "dec 8", "12/8"
///   times: 5pm, 5:30pm, 17:00, noon, midnight, "at 5", "@ 5"
///   course: #CS225
///   estimate: ~45m, ~1h, ~1.5h, ~1h30m, ~2 hours (a leading - works too: -2h)
/// Everything matched is stripped; the remainder is the title.
public enum QuickAddParser {
    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> QuickAddParse {
        // Trailing punctuation ("5pm.", "fri,") should not stop a token from matching.
        let normalized = input.replacingOccurrences(of: #"([.,;!])(?=\s|$)"#, with: " ", options: .regularExpression)
        var text = " \(normalized) "
        var result = QuickAddParse(title: "")

        if let (course, stripped) = extractCourse(from: text) {
            result.course = course
            text = stripped
        }
        if let (minutes, stripped) = extractEstimate(from: text) {
            result.estimateMinutes = minutes
            text = stripped
        }

        var dayComponents: DateComponents?
        var dayOffset: Int?
        var explicitDate: Date?
        var isNext = false

        if let (offset, next, stripped) = extractRelativeDay(from: text, now: now, calendar: calendar) {
            dayOffset = offset
            isNext = next
            text = stripped
        } else if let (date, stripped) = extractAbsoluteDate(from: text, now: now, calendar: calendar) {
            explicitDate = date
            text = stripped
        }

        if let (time, stripped) = extractTime(from: text) {
            dayComponents = time
            result.hasExplicitTime = true
            text = stripped
        }

        result.dueDate = resolveDate(
            dayOffset: dayOffset, isNext: isNext, explicitDate: explicitDate,
            time: dayComponents, now: now, calendar: calendar
        )
        result.title = cleanTitle(text)
        return result
    }

    // MARK: - Pieces

    private static func extractCourse(from text: String) -> (String, String)? {
        guard let m = firstMatch(#"(?<=\s)#([A-Za-z0-9][A-Za-z0-9_-]*)(?=\s)"#, in: text) else { return nil }
        return (m.groups[0], remove(m.range, from: text))
    }

    private static func extractEstimate(from text: String) -> (Int, String)? {
        // ~1h30m / ~1h 30m
        if let m = firstMatch(#"(?<=\s)[~-]\s*(\d+)\s*h(?:rs?|ours?)?\s*(\d+)\s*m(?:in(?:s|utes)?)?(?=\s)"#, in: text) {
            let h = Int(m.groups[0]) ?? 0, mm = Int(m.groups[1]) ?? 0
            return (h * 60 + mm, remove(m.range, from: text))
        }
        // ~45m / ~1.5h / ~2 hours
        if let m = firstMatch(#"(?<=\s)[~-]\s*(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)(?=\s)"#, in: text) {
            let n = Double(m.groups[0]) ?? 0
            let isHours = m.groups[1].hasPrefix("h")
            let minutes = Int((isHours ? n * 60 : n).rounded())
            return (minutes, remove(m.range, from: text))
        }
        return nil
    }

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
    ]

    /// Returns (day offset from today, isNext, stripped text).
    private static func extractRelativeDay(from text: String, now: Date, calendar: Calendar) -> (Int, Bool, String)? {
        if let m = firstMatch(#"(?i)(?<=\s)(today|tonight|tod|eod)(?=\s)"#, in: text) {
            return (0, false, remove(m.range, from: text))
        }
        if let m = firstMatch(#"(?i)(?<=\s)(tomorrow|tmr|tmrw|tmw)(?=\s)"#, in: text) {
            return (1, false, remove(m.range, from: text))
        }
        if let m = firstMatch(#"(?i)(?<=\s)in\s+(\d+)\s*(d|day|days|w|wk|wks|week|weeks)(?=\s)"#, in: text) {
            let n = Int(m.groups[0]) ?? 0
            let mult = m.groups[1].lowercased().hasPrefix("w") ? 7 : 1
            return (n * mult, false, remove(m.range, from: text))
        }
        if let m = firstMatch(#"(?i)(?<=\s)eow(?=\s)"#, in: text) {
            return (offsetToWeekday(6, from: now, calendar: calendar, next: false), false, remove(m.range, from: text))
        }
        let names = weekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let m = firstMatch("(?i)(?<=\\s)(?:(next)\\s+)?(\(names))(?=\\s)", in: text) {
            let isNext = !m.groups[0].isEmpty
            guard let wd = weekdays[m.groups[1].lowercased()] else { return nil }
            return (offsetToWeekday(wd, from: now, calendar: calendar, next: isNext), isNext, remove(m.range, from: text))
        }
        return nil
    }

    /// Days until the upcoming occurrence of `weekday` (1 = Sunday). Same weekday as today = today.
    /// `next` pushes to the occurrence in the following calendar week.
    static func offsetToWeekday(_ weekday: Int, from now: Date, calendar: Calendar, next: Bool) -> Int {
        let todayWD = calendar.component(.weekday, from: now)
        var offset = (weekday - todayWD + 7) % 7
        if next {
            if offset == 0 { offset = 7 }
            let today = calendar.startOfDay(for: now)
            if let candidate = calendar.date(byAdding: .day, value: offset, to: today),
               calendar.isDate(candidate, equalTo: now, toGranularity: .weekOfYear) {
                offset += 7
            }
        }
        return offset
    }

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    private static func extractAbsoluteDate(from text: String, now: Date, calendar: Calendar) -> (Date, String)? {
        let names = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let m = firstMatch("(?i)(?<=\\s)(\(names))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?=\\s)", in: text),
           let month = months[m.groups[0].lowercased()], let day = Int(m.groups[1]) {
            return (nextDate(month: month, day: day, now: now, calendar: calendar), remove(m.range, from: text))
        }
        if let m = firstMatch(#"(?<=\s)(\d{1,2})/(\d{1,2})(?=\s)"#, in: text),
           let month = Int(m.groups[0]), let day = Int(m.groups[1]), (1...12).contains(month), (1...31).contains(day) {
            return (nextDate(month: month, day: day, now: now, calendar: calendar), remove(m.range, from: text))
        }
        return nil
    }

    /// The next occurrence of month/day at or after today (rolls to next year if it already passed).
    private static func nextDate(month: Int, day: Int, now: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: now)
        let today = calendar.startOfDay(for: now)
        for y in [year, year + 1] {
            if let d = calendar.date(from: DateComponents(year: y, month: month, day: day)), d >= today {
                return d
            }
        }
        return today
    }

    private static func extractTime(from text: String) -> (DateComponents, String)? {
        if let m = firstMatch(#"(?i)(?<=\s)noon(?=\s)"#, in: text) {
            return (DateComponents(hour: 12, minute: 0), remove(m.range, from: text))
        }
        if let m = firstMatch(#"(?i)(?<=\s)midnight(?=\s)"#, in: text) {
            return (DateComponents(hour: 23, minute: 59), remove(m.range, from: text))
        }
        // 1230pm, 830am (no colon, with am/pm)
        if let m = firstMatch(#"(?i)(?<=\s)(?:(?:at|@)\s+)?(\d{1,2})(\d{2})\s*(am|pm|a|p)(?=\s)"#, in: text),
           let h = Int(m.groups[0]), let mm = Int(m.groups[1]), (1...12).contains(h), (0...59).contains(mm) {
            let isPM = m.groups[2].lowercased().hasPrefix("p")
            return (DateComponents(hour: (h % 12) + (isPM ? 12 : 0), minute: mm), remove(m.range, from: text))
        }
        // 5pm, 5:30pm, 5 pm, 5p
        if let m = firstMatch(#"(?i)(?<=\s)(?:(?:at|@)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)(?=\s)"#, in: text),
           let h = Int(m.groups[0]), (1...12).contains(h) {
            let minute = Int(m.groups[1]) ?? 0
            let isPM = m.groups[2].lowercased().hasPrefix("p")
            let hour = (h % 12) + (isPM ? 12 : 0)
            return (DateComponents(hour: hour, minute: minute), remove(m.range, from: text))
        }
        // "at 1230" / "@ 830": colon-less clock time, only when preceded by at/@. Same AM/PM guess as "at 5".
        if let m = firstMatch(#"(?i)(?<=\s)(?:at|@)\s+(\d{1,2})(\d{2})(?=\s)"#, in: text),
           let h = Int(m.groups[0]), let mm = Int(m.groups[1]), (0...23).contains(h), (0...59).contains(mm) {
            return (DateComponents(hour: guessHour(h), minute: mm), remove(m.range, from: text))
        }
        // 17:00 / at 17:00
        if let m = firstMatch(#"(?<=\s)(?:(?:at|@)\s+)?(\d{1,2}):(\d{2})(?=\s)"#, in: text),
           let h = Int(m.groups[0]), let mm = Int(m.groups[1]), (0...23).contains(h), (0...59).contains(mm) {
            return (DateComponents(hour: h, minute: mm), remove(m.range, from: text))
        }
        // "at 5" / "@ 5": bare number only when preceded by at/@. 1-6 reads as PM, 7-11 as AM.
        if let m = firstMatch(#"(?i)(?<=\s)(?:at|@)\s+(\d{1,2})(?=\s)"#, in: text),
           let h = Int(m.groups[0]), (1...23).contains(h) {
            return (DateComponents(hour: guessHour(h), minute: 0), remove(m.range, from: text))
        }
        return nil
    }

    /// No am/pm given: 1 to 6 means afternoon, everything else is taken literally (7 to 11 morning, 12 noon, 13+ 24h).
    static func guessHour(_ h: Int) -> Int {
        (1...6).contains(h) ? h + 12 : h
    }

    private static func resolveDate(
        dayOffset: Int?, isNext: Bool, explicitDate: Date?, time: DateComponents?,
        now: Date, calendar: Calendar
    ) -> Date? {
        let baseDay: Date?
        if let explicitDate {
            baseDay = calendar.startOfDay(for: explicitDate)
        } else if let dayOffset {
            baseDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))
        } else {
            baseDay = nil
        }

        guard let time else {
            guard let baseDay else { return nil }
            return DueLogic.endOfDay(baseDay, calendar: calendar)
        }
        let hour = time.hour ?? 23, minute = time.minute ?? 59
        if let baseDay {
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay)
        }
        // Time only: today if still ahead, otherwise tomorrow.
        let today = calendar.startOfDay(for: now)
        guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) else { return nil }
        if candidate > now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    private static func cleanTitle(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Drop dangling connectors left behind by stripped tokens: "essay due" -> "essay".
        while let m = firstMatch(#"(?i)\s+(at|on|by|due|@|-)$"#, in: t) {
            t = String(t[..<m.range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if let m = firstMatch(#"(?i)^(due|by|on|at)\s+"#, in: t) {
            t = String(t[m.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    // MARK: - Regex helpers

    private struct Match {
        let range: Range<String.Index>
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let range = Range(m.range, in: text) else { return nil }
        let groups = (1..<m.numberOfRanges).map { i -> String in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        return Match(range: range, groups: groups)
    }

    private static func remove(_ range: Range<String.Index>, from text: String) -> String {
        var t = text
        t.replaceSubrange(range, with: " ")
        return t
    }
}
