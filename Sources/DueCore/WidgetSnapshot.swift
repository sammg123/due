import Foundation

/// One assignment as the desktop widget draws it. Everything is precomputed so the widget's
/// views stay dumb and every timeline entry is a plain value.
public struct WidgetRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let course: String?
    public let courseColor: PaletteColor
    public let bucket: DueBucket
    /// Short right-aligned label, the same one the popover uses: "5:00 PM", "tomorrow", "2d ago".
    public let dueText: String
}

/// What the widget shows at one moment: open work in the popover's order, capped to what fits,
/// then recently finished work in whatever space is left.
public struct WidgetSnapshot: Equatable, Sendable {
    public let date: Date
    public let rows: [WidgetRow]
    /// Completed items, most recently finished first, in the slots open work leaves free.
    public let doneRows: [WidgetRow]
    /// Every completed item, shown or not.
    public let doneCount: Int
    /// Open items that did not fit under the cap.
    public let hiddenCount: Int
    /// Overdue plus due today: the menu bar number.
    public let todayCount: Int
    public let overdueCount: Int
    public let openCount: Int

    public var isEmpty: Bool { openCount == 0 }

    /// "2 overdue · 1 due today", "3 due today", "Nothing due today", "All caught up".
    public var headline: String {
        if isEmpty { return "All caught up" }
        let dueToday = todayCount - overdueCount
        var parts: [String] = []
        if overdueCount > 0 { parts.append("\(overdueCount) overdue") }
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        return parts.isEmpty ? "Nothing due today" : parts.joined(separator: " · ")
    }

    /// Label under the small widget's big `todayCount`, so the number never claims "due today"
    /// for work that is already late.
    public var countCaption: String {
        if overdueCount == 0 { return "due today" }
        return overdueCount == todayCount ? "overdue" : "due or overdue"
    }

    public static func make(from data: AppData, now: Date, limit: Int, calendar: Calendar = .current) -> WidgetSnapshot {
        let groups = DueLogic.grouped(data.assignments, now: now, settings: data.settings, calendar: calendar)
        let open = groups.filter { $0.bucket != .done }
        let finished = groups.first { $0.bucket == .done }?.items ?? []
        let ordered = open.flatMap { group in group.items.map { (group.bucket, $0) } }
        let row = { (bucket: DueBucket, a: Assignment) in
            WidgetRow(
                id: a.id,
                title: a.title,
                course: a.course,
                courseColor: a.course.flatMap { data.courseColors[$0] } ?? .gray,
                bucket: bucket,
                dueText: DueLogic.relativeDueText(for: a.dueDate, now: now, calendar: calendar)
            )
        }
        let shown = ordered.prefix(max(0, limit)).map(row)
        let doneShown = finished.prefix(max(0, limit - shown.count)).map { row(.done, $0) }
        let overdue = open.first { $0.bucket == .overdue }?.items.count ?? 0
        let today = open.first { $0.bucket == .today }?.items.count ?? 0
        return WidgetSnapshot(
            date: now,
            rows: Array(shown),
            doneRows: Array(doneShown),
            doneCount: finished.count,
            hiddenCount: ordered.count - shown.count,
            todayCount: overdue + today,
            overdueCount: overdue,
            openCount: ordered.count
        )
    }
}

/// When the widget should redraw on its own, between reloads the app or a checkbox triggers.
public enum WidgetTimeline {
    /// Often enough that "12m ago" and "3h ago" never read badly stale.
    public static let tick: TimeInterval = 5 * 60
    /// How far ahead one timeline reaches before WidgetKit asks for a new one.
    public static let horizon: TimeInterval = 3 * 60 * 60

    /// Now, a regular tick, plus the exact moments something changes bucket: an open item
    /// falling due, and midnight. Sorted, unique, all within `horizon`.
    public static func entryDates(for data: AppData, from now: Date, calendar: Calendar = .current) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        let ticks = (0...Int(horizon / tick)).map { now.addingTimeInterval(Double($0) * tick) }
        let dueMoments = data.assignments
            .filter { !$0.isDone && $0.dueDate > now && $0.dueDate <= end }
            .map(\.dueDate)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            .map { $0 <= end ? [$0] : [] } ?? []
        return Array(Set(ticks + dueMoments + midnight)).sorted()
    }
}
