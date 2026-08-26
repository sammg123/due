import XCTest
@testable import DueCore

/// `DueLogic`'s text formatters (weekdayFormatter, monthDayFormatter, timeFormatter, ...) are built with
/// a bare `DateFormatter()`, which resolves its time zone from `NSTimeZone.default` at format time rather
/// than from the `calendar` parameter passed into `relativeDueText`. In production that's harmless because
/// callers always pass `calendar: .current`, so the two agree. For deterministic tests against a fixed
/// America/Chicago calendar we pin `NSTimeZone.default` for the duration of each test and restore it after,
/// rather than touching source.
final class DueLogicTests: XCTestCase {
    private var cal: Calendar!
    private var now: Date!
    private var originalTimeZone: TimeZone!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
        now = date(2026, 8, 26, 10, 0) // Wednesday
        originalTimeZone = NSTimeZone.default as TimeZone
        NSTimeZone.default = cal.timeZone
    }

    override func tearDown() {
        NSTimeZone.default = originalTimeZone
        super.tearDown()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func assignment(
        due: Date,
        isDone: Bool = false,
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSinceReferenceDate: 0),
        estimateMinutes: Int? = nil,
        title: String = "A"
    ) -> Assignment {
        Assignment(
            title: title,
            dueDate: due,
            estimateMinutes: estimateMinutes,
            isDone: isDone,
            completedAt: completedAt,
            createdAt: createdAt,
            sortOrder: sortOrder
        )
    }

    // MARK: - bucket(for:)

    func test_bucket_returnsDone_whenAssignmentIsDone() {
        // Arrange
        let a = assignment(due: date(2026, 8, 20), isDone: true)
        // Act
        let bucket = DueLogic.bucket(for: a, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(bucket, .done)
    }

    func test_bucket_returnsOverdue_whenDueOneMinuteAgo() {
        let a = assignment(due: now.addingTimeInterval(-60))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .overdue)
    }

    func test_bucket_returnsToday_whenDueLaterToday() {
        let a = assignment(due: date(2026, 8, 26, 20, 0))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .today)
    }

    func test_bucket_returnsSoon_whenDueInTwoDays() {
        let a = assignment(due: date(2026, 8, 28, 10, 0))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .soon)
    }

    func test_bucket_returnsSoon_whenDueInThreeDays() {
        let a = assignment(due: date(2026, 8, 29, 10, 0))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .soon)
    }

    func test_bucket_returnsThisWeek_whenDueInFourDays() {
        let a = assignment(due: date(2026, 8, 30, 10, 0))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .thisWeek)
    }

    func test_bucket_returnsThisWeek_whenDueInSevenDays() {
        let a = assignment(due: date(2026, 9, 2, 10, 0))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .thisWeek)
    }

    func test_bucket_returnsLater_whenDueInEightDays() {
        let a = assignment(due: date(2026, 9, 3, 10, 0))
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, calendar: cal), .later)
    }

    func test_bucket_customSettings_narrowsSoonWindowIntoThisWeek() {
        // soonDays: 1 means the default-soon 2-day-out item no longer qualifies as soon...
        let settings = DueSettings(soonDays: 1, weekDays: 3)
        let a = assignment(due: date(2026, 8, 28, 10, 0)) // 2 days out
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, settings: settings, calendar: cal), .thisWeek)
    }

    func test_bucket_customSettings_narrowWeekDaysPushesIntoLater() {
        // ...and weekDays: 3 means the default-thisWeek 4-day-out item now falls past the window into later.
        let settings = DueSettings(soonDays: 1, weekDays: 3)
        let a = assignment(due: date(2026, 8, 30, 10, 0)) // 4 days out
        XCTAssertEqual(DueLogic.bucket(for: a, now: now, settings: settings, calendar: cal), .later)
    }

    // MARK: - grouped()

    func test_grouped_omitsEmptyBuckets() {
        let items = [assignment(due: date(2026, 8, 26, 20, 0))] // today only
        let groups = DueLogic.grouped(items, now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.bucket), [.today])
    }

    func test_grouped_ordersBucketsOverdueToDone() {
        let items = [
            assignment(due: date(2026, 9, 10), isDone: true, completedAt: now, title: "done-item"),
            assignment(due: date(2026, 9, 3, 10, 0), title: "later-item"),
            assignment(due: now.addingTimeInterval(-60), title: "overdue-item"),
            assignment(due: date(2026, 8, 26, 20, 0), title: "today-item"),
        ]
        let groups = DueLogic.grouped(items, now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.bucket), [.overdue, .today, .later, .done])
    }

    func test_grouped_sortsOpenItems_bySortOrderThenDueDateThenCreatedAt() {
        let earlyCreated = date(2020, 1, 1)
        let lateCreated = date(2020, 1, 2)
        // All four are in the "this week" bucket (4-5 days out from `now`).
        let secondByOrder = assignment(due: date(2026, 8, 30, 12, 0), sortOrder: 1, createdAt: earlyCreated, title: "second-by-order")
        let firstByOrder = assignment(due: date(2026, 8, 31, 12, 0), sortOrder: 0, createdAt: earlyCreated, title: "first-by-order")
        let earlierDueAmongOrder1 = assignment(due: date(2026, 8, 30, 8, 0), sortOrder: 1, createdAt: earlyCreated, title: "earlier-due-among-order-1")
        let laterCreatedTiebreak = assignment(due: date(2026, 8, 30, 12, 0), sortOrder: 1, createdAt: lateCreated, title: "later-created-tiebreak")

        let items = [secondByOrder, firstByOrder, earlierDueAmongOrder1, laterCreatedTiebreak]
        let groups = DueLogic.grouped(items, now: now, calendar: cal)
        let thisWeek = groups.first { $0.bucket == .thisWeek }!

        XCTAssertEqual(
            thisWeek.items.map(\.title),
            ["first-by-order", "earlier-due-among-order-1", "second-by-order", "later-created-tiebreak"]
        )
    }

    func test_grouped_sortsDoneItems_byCompletedAtDescending() {
        let older = assignment(due: date(2026, 8, 20), isDone: true, completedAt: date(2026, 8, 20, 9, 0), title: "older")
        let newer = assignment(due: date(2026, 8, 21), isDone: true, completedAt: date(2026, 8, 22, 9, 0), title: "newer")
        let groups = DueLogic.grouped([older, newer], now: now, calendar: cal)
        let done = groups.first { $0.bucket == .done }!
        XCTAssertEqual(done.items.map(\.title), ["newer", "older"])
    }

    // MARK: - todayCount

    func test_todayCount_countsOnlyOverdueAndToday() {
        let items = [
            assignment(due: now.addingTimeInterval(-60), title: "overdue"),
            assignment(due: date(2026, 8, 26, 20, 0), title: "today"),
            assignment(due: date(2026, 8, 28, 10, 0), title: "soon"),
            assignment(due: date(2026, 8, 20), isDone: true, title: "done"),
        ]
        XCTAssertEqual(DueLogic.todayCount(items, now: now, calendar: cal), 2)
    }

    // MARK: - relativeDueText

    func test_relativeDueText_minutesAgo() {
        let d = now.addingTimeInterval(-5 * 60)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "5m ago")
    }

    func test_relativeDueText_hoursAgo() {
        let d = now.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "2h ago")
    }

    func test_relativeDueText_yesterday() {
        let d = date(2026, 8, 25, 20, 0)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "yesterday")
    }

    func test_relativeDueText_daysAgo() {
        let d = date(2026, 8, 24, 20, 0)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "2d ago")
    }

    func test_relativeDueText_endOfDayToday_showsToday() {
        let d = DueLogic.endOfDay(date(2026, 8, 26), calendar: cal) // 11:59 PM today
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "today")
    }

    func test_relativeDueText_todayWithExplicitTime_showsClockTime() {
        let d = date(2026, 8, 26, 14, 30)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "2:30 PM")
    }

    func test_relativeDueText_tomorrow() {
        let d = date(2026, 8, 27, 9, 0)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "tomorrow")
    }

    func test_relativeDueText_weekdayAbbreviation_whenLessThanSevenDaysOut() {
        let d = date(2026, 8, 29, 9, 0) // Saturday, 3 days out
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "Sat")
    }

    func test_relativeDueText_monthDay_whenSameYear() {
        let d = date(2026, 9, 5, 9, 0)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "Sep 5")
    }

    func test_relativeDueText_monthDayYear_whenDifferentYear() {
        let d = date(2027, 1, 15, 9, 0)
        XCTAssertEqual(DueLogic.relativeDueText(for: d, now: now, calendar: cal), "Jan 15, 2027")
    }

    // MARK: - estimateText

    func test_estimateText_under1Hour_showsMinutesOnly() {
        XCTAssertEqual(DueLogic.estimateText(minutes: 45), "45m")
    }

    func test_estimateText_exactHour_showsHoursOnly() {
        XCTAssertEqual(DueLogic.estimateText(minutes: 60), "1h")
    }

    func test_estimateText_hourPlusMinutes_showsBoth() {
        XCTAssertEqual(DueLogic.estimateText(minutes: 90), "1h 30m")
    }

    // MARK: - openEstimateMinutesThisWeek

    func test_openEstimateMinutesThisWeek_includesOverdueTodaySoonThisWeek_excludesLaterDoneAndNilEstimates() {
        let items = [
            assignment(due: now.addingTimeInterval(-60), estimateMinutes: 10, title: "overdue"),
            assignment(due: date(2026, 8, 26, 20, 0), estimateMinutes: 20, title: "today"),
            assignment(due: date(2026, 8, 28, 10, 0), estimateMinutes: 30, title: "soon"),
            assignment(due: date(2026, 8, 30, 10, 0), estimateMinutes: 40, title: "thisWeek"),
            assignment(due: date(2026, 9, 3, 10, 0), estimateMinutes: 50, title: "later"),
            assignment(due: date(2026, 8, 20), isDone: true, estimateMinutes: 999, title: "done"),
            assignment(due: date(2026, 8, 28, 12, 0), estimateMinutes: nil, title: "soon-no-estimate"),
        ]
        XCTAssertEqual(DueLogic.openEstimateMinutesThisWeek(items, now: now, calendar: cal), 100)
    }
}
