import Foundation

public enum DueBucket: Int, CaseIterable, Comparable, Sendable {
    case overdue, today, soon, thisWeek, later, done

    public static func < (lhs: DueBucket, rhs: DueBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .soon: return "Soon"
        case .thisWeek: return "This week"
        case .later: return "Later"
        case .done: return "Done"
        }
    }

    /// Urgency color. Done is gray.
    public var paletteColor: PaletteColor {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .soon: return .yellow
        case .thisWeek: return .blue
        case .later: return .gray
        case .done: return .gray
        }
    }
}

public struct BucketGroup: Identifiable, Equatable, Sendable {
    public let bucket: DueBucket
    public let items: [Assignment]
    public var id: DueBucket { bucket }
    public init(bucket: DueBucket, items: [Assignment]) {
        self.bucket = bucket
        self.items = items
    }
}

public enum DueLogic {
    public static func bucket(
        for assignment: Assignment,
        now: Date = Date(),
        settings: DueSettings = DueSettings(),
        calendar: Calendar = .current
    ) -> DueBucket {
        if assignment.isDone { return .done }
        if assignment.dueDate < now { return .overdue }
        let days = dayDistance(from: now, to: assignment.dueDate, calendar: calendar)
        if days <= 0 { return .today }
        if days <= settings.soonDays { return .soon }
        if days <= settings.weekDays { return .thisWeek }
        return .later
    }

    /// Whole calendar days between the two dates (start-of-day to start-of-day).
    public static func dayDistance(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Bucket order, empty buckets omitted. Open items sort by manual order, then due date, then creation.
    /// Done items sort by most recently completed first.
    public static func grouped(
        _ items: [Assignment],
        now: Date = Date(),
        settings: DueSettings = DueSettings(),
        calendar: Calendar = .current
    ) -> [BucketGroup] {
        let tagged = items.map { ($0, bucket(for: $0, now: now, settings: settings, calendar: calendar)) }
        return DueBucket.allCases.compactMap { b in
            let members = tagged.filter { $0.1 == b }.map(\.0)
            guard !members.isEmpty else { return nil }
            return BucketGroup(bucket: b, items: sorted(members, in: b))
        }
    }

    public static func sorted(_ items: [Assignment], in bucket: DueBucket) -> [Assignment] {
        if bucket == .done {
            return items.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
        return items.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            return $0.createdAt < $1.createdAt
        }
    }

    /// Open items that are overdue or due today. This is the menu bar number.
    public static func todayCount(_ items: [Assignment], now: Date = Date(), calendar: Calendar = .current) -> Int {
        items.filter {
            let b = bucket(for: $0, now: now, calendar: calendar)
            return b == .overdue || b == .today
        }.count
    }

    /// Short right-aligned label for a row: "2d ago", "5:00 PM", "Thu", "Dec 8".
    public static func relativeDueText(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = dayDistance(from: now, to: date, calendar: calendar)
        if date < now {
            let secs = now.timeIntervalSince(date)
            if days == 0 {
                if secs < 3600 { return "\(max(1, Int(secs / 60)))m ago" }
                return "\(Int(secs / 3600))h ago"
            }
            if days == -1 { return "yesterday" }
            return "\(-days)d ago"
        }
        if days == 0 {
            return isEndOfDay(date, calendar: calendar) ? "today" : timeText(date)
        }
        if days == 1 { return "tomorrow" }
        if days < 7 { return weekdayFormatter.string(from: date) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDayFormatter.string(from: date)
        }
        return monthDayYearFormatter.string(from: date)
    }

    /// Longer label for hovers/editing: "Thu, Dec 8 at 5:00 PM".
    public static func fullDueText(for date: Date, calendar: Calendar = .current) -> String {
        let day = fullDayFormatter.string(from: date)
        return isEndOfDay(date, calendar: calendar) ? day : "\(day) at \(timeText(date))"
    }

    public static func isEndOfDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour == 23 && c.minute == 59
    }

    public static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
    }

    public static func timeText(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// "45m", "1h", "1h 30m".
    public static func estimateText(minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Minutes of open work due within `settings.weekDays` days, overdue included (it still has to be done).
    public static func openEstimateMinutesThisWeek(
        _ items: [Assignment],
        now: Date = Date(),
        settings: DueSettings = DueSettings(),
        calendar: Calendar = .current
    ) -> Int {
        items.reduce(0) { total, a in
            guard !a.isDone, let est = a.estimateMinutes else { return total }
            let b = bucket(for: a, now: now, settings: settings, calendar: calendar)
            return b == .later ? total : total + est
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private static let monthDayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
