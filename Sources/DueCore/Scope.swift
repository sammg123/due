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

    /// "Aug 24 to 30" or "Aug 31 to Sep 6", plus "This week" / "Next week" / "Last week" when it applies.
    static func weekTitle(_ week: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> String {
        let thisWeek = weekInterval(containing: now, calendar: calendar)
        let weeksAway = calendar.dateComponents([.weekOfYear], from: thisWeek.start, to: week.start).weekOfYear ?? 0
        switch weeksAway {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        default: break
        }
        let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        let startText = shortMonthDay.string(from: week.start)
        let sameMonth = calendar.isDate(week.start, equalTo: end, toGranularity: .month)
        let endText = sameMonth ? dayOnly.string(from: end) : shortMonthDay.string(from: end)
        return "\(startText) to \(endText)"
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
}
