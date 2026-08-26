import Foundation

/// Validated output of an on-device language model parse. Built from the model's raw strings so the
/// validation is testable without the model. Any field the model left blank or malformed is nil.
public struct SmartParseResult: Equatable, Sendable {
    public var title: String?
    public var day: DateComponents?          // year, month, day
    public var time: DateComponents?         // hour, minute
    public var course: String?
    public var estimateMinutes: Int?

    public init(title: String? = nil, day: DateComponents? = nil, time: DateComponents? = nil, course: String? = nil, estimateMinutes: Int? = nil) {
        self.title = title
        self.day = day
        self.time = time
        self.course = course
        self.estimateMinutes = estimateMinutes
    }

    /// `dateString` "YYYY-MM-DD", `timeString` "HH:MM" (24h). `knownCourses` lets a loose course
    /// mention ("writing class", "writ 150") snap to the real name.
    public init(title: String, dateString: String, timeString: String, course: String, estimateMinutes: Int, knownCourses: [String]) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = cleanTitle.isEmpty ? nil : cleanTitle
        self.day = Self.parseDay(dateString)
        self.time = Self.parseTime(timeString)
        self.course = Self.matchCourse(course, known: knownCourses)
        self.estimateMinutes = estimateMinutes > 0 ? estimateMinutes : nil
    }

    static func parseDay(_ s: String) -> DateComponents? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (2000...2100).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    static func parseTime(_ s: String) -> DateComponents? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return DateComponents(hour: parts[0], minute: parts[1])
    }

    /// Exact (case-insensitive, whitespace-insensitive) match first, then a known course whose
    /// letters-only prefix matches ("writ" -> "WRIT150"), else the model's text as typed.
    static func matchCourse(_ raw: String, known: [String]) -> String? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let k = key(clean)
        if let exact = known.first(where: { key($0) == k }) { return exact }
        // Letters-only prefix in either direction: "writ" -> WRIT150, "writing" -> WRIT150.
        let letters = k.filter(\.isLetter)
        if letters.count >= 3, let prefix = known.first(where: { candidate in
            let known = key(candidate).filter(\.isLetter)
            return known.count >= 3 && (letters.hasPrefix(known) || known.hasPrefix(letters))
        }) { return prefix }
        if let contained = known.first(where: { key($0).contains(k) || k.contains(key($0)) }) { return contained }
        return clean
    }
}

public extension QuickAddParse {
    /// Precedence, measured against the on-device model (2026-08-26): the regex parser is exact on
    /// every date phrase it recognizes, while the model gets weekday arithmetic wrong ("next fri",
    /// "end of week"). So the regex DAY always wins when it found one; the model only supplies a day
    /// the regex could not read. Times: an explicit regex time wins, else the model's. Title, course
    /// and estimate: the model wins (it is better at stripping words and mapping course names).
    /// A day with no time is due 11:59 PM; a time with no day is today or tomorrow.
    func merging(_ smart: SmartParseResult, now: Date = Date(), calendar: Calendar = .current) -> QuickAddParse {
        var merged = self
        if let t = smart.title { merged.title = t }
        if let c = smart.course { merged.course = c }
        if let e = smart.estimateMinutes { merged.estimateMinutes = e }

        let regexTime: DateComponents? = hasExplicitTime && dueDate != nil
            ? calendar.dateComponents([.hour, .minute], from: dueDate!) : nil
        let time = regexTime ?? smart.time

        if let regexDay = dueDate {
            // Regex owns the day. The model may still fill in a time the regex did not read.
            if regexTime == nil, let smartTime = smart.time {
                merged.dueDate = calendar.date(
                    bySettingHour: smartTime.hour ?? 23, minute: smartTime.minute ?? 59, second: 0,
                    of: calendar.startOfDay(for: regexDay)
                )
                merged.hasExplicitTime = true
            }
        } else if let dayComponents = smart.day, let day = calendar.date(from: dayComponents) {
            let start = calendar.startOfDay(for: day)
            if let time {
                merged.dueDate = calendar.date(bySettingHour: time.hour ?? 23, minute: time.minute ?? 59, second: 0, of: start)
                merged.hasExplicitTime = true
            } else {
                merged.dueDate = DueLogic.endOfDay(start, calendar: calendar)
                merged.hasExplicitTime = false
            }
        } else if let time = smart.time {
            let today = calendar.startOfDay(for: now)
            let candidate = calendar.date(bySettingHour: time.hour ?? 23, minute: time.minute ?? 59, second: 0, of: today) ?? today
            merged.dueDate = candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)
            merged.hasExplicitTime = true
        }
        return merged
    }
}
