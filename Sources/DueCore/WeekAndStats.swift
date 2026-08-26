import Foundation

/// One column of the 7-day load strip.
public struct WeekDay: Identifiable, Equatable, Sendable {
    public let date: Date
    /// Open items due on this day. Today's count also folds in overdue items (they are still load).
    public let count: Int
    public let isToday: Bool
    public var id: Date { date }

    public init(date: Date, count: Int, isToday: Bool) {
        self.date = date
        self.count = count
        self.isToday = isToday
    }

    /// Single letter: M T W T F S S.
    public var weekdayLetter: String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    /// "Wed".
    public var weekdayShort: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    /// Day of month, "26".
    public var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }
}

public struct DoneStats: Equatable, Sendable {
    public let completedThisWeek: Int
    public let onTimeCount: Int
    public let lateCount: Int
    public let totalDone: Int

    public init(completedThisWeek: Int, onTimeCount: Int, lateCount: Int, totalDone: Int) {
        self.completedThisWeek = completedThisWeek
        self.onTimeCount = onTimeCount
        self.lateCount = lateCount
        self.totalDone = totalDone
    }

    /// Across all done items. Nil when nothing is done yet.
    public var onTimeRate: Double? {
        let judged = onTimeCount + lateCount
        guard judged > 0 else { return nil }
        return Double(onTimeCount) / Double(judged)
    }
}

public extension DueLogic {
    /// Today plus the next 6 days.
    static func weekLoad(_ items: [Assignment], now: Date = Date(), calendar: Calendar = .current) -> [WeekDay] {
        let today = calendar.startOfDay(for: now)
        let open = items.filter { !$0.isDone }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let dueThatDay = open.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }.count
            let overdue = offset == 0 ? open.filter { $0.dueDate < today }.count : 0
            return WeekDay(date: day, count: dueThatDay + overdue, isToday: offset == 0)
        }
    }

    /// "This week" is the calendar week containing `now`.
    static func doneStats(_ items: [Assignment], now: Date = Date(), calendar: Calendar = .current) -> DoneStats {
        let done = items.filter { $0.isDone }
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let thisWeek = done.filter { a in
            guard let c = a.completedAt, let week else { return false }
            return week.contains(c)
        }.count
        let onTime = done.filter { ($0.completedAt ?? .distantFuture) <= $0.dueDate }.count
        return DoneStats(
            completedThisWeek: thisWeek,
            onTimeCount: onTime,
            lateCount: done.count - onTime,
            totalDone: done.count
        )
    }
}
