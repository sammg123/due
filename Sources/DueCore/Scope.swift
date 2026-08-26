import Foundation

/// What the list is currently showing.
public enum ListScope: Equatable, Sendable {
    case all
    case day(Date)
    case week(DateInterval)

    public var isAll: Bool { if case .all = self { return true } else { return false } }
}

public extension DueLogic {
    /// The calendar week containing `date`, shifted by `offsetWeeks`. Start respects `calendar.firstWeekday`.
    static func weekInterval(containing date: Date, offsetWeeks: Int = 0, calendar: Calendar = .current) -> DateInterval {
        let base = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
        guard offsetWeeks != 0,
              let start = calendar.date(byAdding: .weekOfYear, value: offsetWeeks, to: base.start),
              let shifted = calendar.dateInterval(of: .weekOfYear, for: start) else { return base }
        return shifted
    }

    /// Seven columns for the given week. Today's column folds in overdue items (they are still load).
    static func weekLoad(_ items: [Assignment], week: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> [WeekDay] {
        let open = items.filter { !$0.isDone }
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let isToday = calendar.isDate(day, inSameDayAs: today)
            let dueThatDay = open.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }.count
            let overdue = isToday ? open.filter { $0.dueDate < today }.count : 0
            return WeekDay(date: day, count: dueThatDay + overdue, isToday: isToday)
        }
    }

    /// Narrows by course and by scope. Done items are kept so a day view can show what was finished.
    static func filter(_ items: [Assignment], course: String?, scope: ListScope, calendar: Calendar = .current) -> [Assignment] {
        items.filter { item in
            if let course, item.course != course { return false }
            switch scope {
            case .all: return true
            case .day(let day): return calendar.isDate(item.dueDate, inSameDayAs: day)
            case .week(let interval): return interval.contains(item.dueDate)
            }
        }
    }

    /// Always carries the dates: "This week · Aug 23 to 29", "Next week · Aug 30 to Sep 5", "Sep 7 to 13".
    static func weekTitle(_ week: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> String {
        let thisWeek = weekInterval(containing: now, calendar: calendar)
        let weeksAway = calendar.dateComponents([.weekOfYear], from: thisWeek.start, to: week.start).weekOfYear ?? 0
        let range = weekRangeText(week, calendar: calendar)
        switch weeksAway {
        case 0: return "This week · \(range)"
        case 1: return "Next week · \(range)"
        case -1: return "Last week · \(range)"
        default: return range
        }
    }

    /// "Aug 24 to 30" or "Aug 31 to Sep 6".
    static func weekRangeText(_ week: DateInterval, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        let startText = shortMonthDay.string(from: week.start)
        let sameMonth = calendar.isDate(week.start, equalTo: end, toGranularity: .month)
        let endText = sameMonth ? dayOnly.string(from: end) : shortMonthDay.string(from: end)
        return "\(startText) to \(endText)"
    }

    /// Row date line, always with the weekday: "Thu, Aug 27", or "Thu, Aug 27, 2027" in another year.
    static func dueDateLine(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return fullDay.string(from: date)
        }
        return fullDayYear.string(from: date)
    }

    /// Row second line: how far away ("today", "tomorrow", "in 5d", "2d ago"), with the clock time first when one was set.
    static func dueDetailLine(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let distance = distanceText(for: date, now: now, calendar: calendar)
        if isEndOfDay(date, calendar: calendar) { return distance }
        return "\(timeText(date)) · \(distance)"
    }

    /// "2d ago", "3h ago", "today", "tomorrow", "in 5d".
    static func distanceText(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = dayDistance(from: now, to: date, calendar: calendar)
        if date < now { return relativeDueText(for: date, now: now, calendar: calendar) }
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "in \(days)d"
    }

    /// "Thu, Aug 27".
    static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return fullDay.string(from: day)
    }

    private static let shortMonthDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
    private static let dayOnly: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()
    private static let fullDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    private static let fullDayYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy"; return f }()
}
