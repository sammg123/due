import XCTest
@testable import DueCore

/// Same time zone pinning as `DueLogicTests`: the row due text comes from `DueLogic`'s
/// formatters, which read `NSTimeZone.default` rather than the calendar passed in.
final class WidgetSnapshotTests: XCTestCase {
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

    private func item(_ title: String, due: Date, course: String? = nil, isDone: Bool = false, sortOrder: Int = 0) -> Assignment {
        Assignment(
            title: title,
            course: course,
            dueDate: due,
            isDone: isDone,
            completedAt: isDone ? now : nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            sortOrder: sortOrder
        )
    }

    private func data(_ items: [Assignment], colors: [String: PaletteColor] = [:], settings: DueSettings = DueSettings()) -> AppData {
        AppData(assignments: items, courseColors: colors, settings: settings)
    }

    private func snapshot(_ data: AppData, limit: Int = 10) -> WidgetSnapshot {
        WidgetSnapshot.make(from: data, now: now, limit: limit, calendar: cal)
    }

    // MARK: - Rows

    func test_rows_areOpenItemsInBucketOrder_doneExcluded() {
        // Arrange: inserted out of order, with sortOrder deliberately not matching urgency.
        let later = item("Later", due: date(2026, 9, 20), sortOrder: 0)
        let today = item("Today", due: date(2026, 8, 26, 17, 0), sortOrder: 1)
        let overdue = item("Overdue", due: date(2026, 8, 25, 9, 0), sortOrder: 2)
        let soon = item("Soon", due: date(2026, 8, 28, 23, 59), sortOrder: 3)
        let week = item("Week", due: date(2026, 9, 1, 23, 59), sortOrder: 4)
        let done = item("Done", due: date(2026, 8, 26, 12, 0), isDone: true, sortOrder: 5)

        // Act
        let snap = snapshot(data([later, today, overdue, soon, week, done]))

        // Assert
        XCTAssertEqual(snap.rows.map(\.title), ["Overdue", "Today", "Soon", "Week", "Later"])
        XCTAssertEqual(snap.rows.map(\.bucket), [.overdue, .today, .soon, .thisWeek, .later])
    }

    func test_rows_withinABucket_followManualOrderLikeThePopover() {
        let first = item("First", due: date(2026, 8, 26, 18, 0), sortOrder: 0)
        let second = item("Second", due: date(2026, 8, 26, 12, 0), sortOrder: 1)

        let snap = snapshot(data([second, first]))

        XCTAssertEqual(snap.rows.map(\.title), ["First", "Second"])
    }

    func test_limit_capsRows_andCountsTheRestAsHidden() {
        let items = (0..<5).map { item("A\($0)", due: date(2026, 8, 27), sortOrder: $0) }

        let snap = snapshot(data(items), limit: 3)

        XCTAssertEqual(snap.rows.map(\.title), ["A0", "A1", "A2"])
        XCTAssertEqual(snap.hiddenCount, 2)
    }

    func test_limitZeroOrNegative_hidesEverything() {
        let items = [item("A", due: date(2026, 8, 27)), item("B", due: date(2026, 8, 28))]

        XCTAssertEqual(snapshot(data(items), limit: 0).rows, [])
        XCTAssertEqual(snapshot(data(items), limit: 0).hiddenCount, 2)
        XCTAssertEqual(snapshot(data(items), limit: -3).rows, [])
    }

    func test_row_carriesIdCourseColorAndShortDueText() {
        let a = item("Essay", due: date(2026, 8, 26, 17, 0), course: "WRIT150")

        let row = snapshot(data([a], colors: ["WRIT150": .teal])).rows[0]

        XCTAssertEqual(row.id, a.id)
        XCTAssertEqual(row.title, "Essay")
        XCTAssertEqual(row.course, "WRIT150")
        XCTAssertEqual(row.courseColor, .teal)
        XCTAssertEqual(row.dueText, DueLogic.relativeDueText(for: a.dueDate, now: now, calendar: cal))
        XCTAssertEqual(row.dueText, "5:00 PM")
    }

    func test_row_withoutCourseOrKnownColor_isGray() {
        let noCourse = item("A", due: date(2026, 8, 27))
        let unknownCourse = item("B", due: date(2026, 8, 27), course: "BUAD312", sortOrder: 1)

        let rows = snapshot(data([noCourse, unknownCourse])).rows

        XCTAssertEqual(rows.map(\.courseColor), [.gray, .gray])
        XCTAssertNil(rows[0].course)
    }

    func test_buckets_respectTheUsersSoonSetting() {
        let fiveDaysOut = item("A", due: date(2026, 8, 31, 23, 59))
        let settings = DueSettings(soonDays: 5, weekDays: 7)

        let snap = snapshot(data([fiveDaysOut], settings: settings))

        XCTAssertEqual(snap.rows[0].bucket, .soon)
    }

    // MARK: - Counts

    func test_counts_matchTheMenuBarNumberAndOpenTotal() {
        let items = [
            item("Overdue", due: date(2026, 8, 25)),
            item("Today", due: date(2026, 8, 26, 23, 59)),
            item("Tomorrow", due: date(2026, 8, 27, 23, 59)),
            item("Done", due: date(2026, 8, 26, 12, 0), isDone: true),
        ]

        let snap = snapshot(data(items))

        XCTAssertEqual(snap.overdueCount, 1)
        XCTAssertEqual(snap.todayCount, 2) // overdue + today, the same number the menu bar shows
        XCTAssertEqual(snap.todayCount, DueLogic.todayCount(items, now: now, calendar: cal))
        XCTAssertEqual(snap.openCount, 3)
        XCTAssertFalse(snap.isEmpty)
    }

    // MARK: - Headline

    func test_headline_nothingOpen_isAllCaughtUp() {
        let snap = snapshot(data([item("Done", due: date(2026, 8, 26), isDone: true)]))
        XCTAssertTrue(snap.isEmpty)
        XCTAssertEqual(snap.headline, "All caught up")
    }

    func test_headline_openButNothingToday() {
        let snap = snapshot(data([item("A", due: date(2026, 8, 29))]))
        XCTAssertEqual(snap.headline, "Nothing due today")
    }

    func test_headline_dueTodayOnly() {
        let snap = snapshot(data([item("A", due: date(2026, 8, 26, 23, 59)), item("B", due: date(2026, 8, 26, 17, 0))]))
        XCTAssertEqual(snap.headline, "2 due today")
    }

    func test_headline_overdueOnly() {
        let snap = snapshot(data([item("A", due: date(2026, 8, 24))]))
        XCTAssertEqual(snap.headline, "1 overdue")
    }

    func test_headline_overdueAndToday() {
        let snap = snapshot(data([
            item("A", due: date(2026, 8, 24)),
            item("B", due: date(2026, 8, 25)),
            item("C", due: date(2026, 8, 26, 23, 59)),
        ]))
        XCTAssertEqual(snap.headline, "2 overdue · 1 due today")
    }

    func test_snapshotDate_isTheNowItWasBuiltFor() {
        XCTAssertEqual(snapshot(data([])).date, now)
    }

    // MARK: - Done rows (fill the space open work leaves)

    private func done(_ title: String, completed: Date, course: String? = nil) -> Assignment {
        Assignment(
            title: title,
            course: course,
            dueDate: date(2026, 8, 20),
            isDone: true,
            completedAt: completed,
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    func test_doneRows_fillTheSlotsOpenWorkLeaves_mostRecentlyCompletedFirst() {
        // Arrange
        let open = item("Open", due: date(2026, 8, 27))
        let older = done("Older", completed: date(2026, 8, 24, 9, 0))
        let newest = done("Newest", completed: date(2026, 8, 26, 9, 0))
        let middle = done("Middle", completed: date(2026, 8, 25, 9, 0))

        // Act
        let snap = snapshot(data([older, open, newest, middle]), limit: 3)

        // Assert
        XCTAssertEqual(snap.rows.map(\.title), ["Open"])
        XCTAssertEqual(snap.doneRows.map(\.title), ["Newest", "Middle"])
        XCTAssertEqual(snap.doneRows.map(\.bucket), [.done, .done])
        XCTAssertEqual(snap.doneCount, 3)
    }

    func test_doneRows_none_whenOpenWorkFillsTheLimit() {
        let open = (0..<3).map { item("A\($0)", due: date(2026, 8, 27), sortOrder: $0) }
        let finished = done("Finished", completed: date(2026, 8, 26, 9, 0))

        let snap = snapshot(data(open + [finished]), limit: 3)

        XCTAssertEqual(snap.rows.count, 3)
        XCTAssertEqual(snap.doneRows, [])
        XCTAssertEqual(snap.doneCount, 1)
    }

    func test_doneRows_carryCourseColorAndDueText() {
        let finished = done("Essay", completed: date(2026, 8, 26, 9, 0), course: "WRIT150")

        let row = snapshot(data([finished], colors: ["WRIT150": .pink])).doneRows[0]

        XCTAssertEqual(row.id, finished.id)
        XCTAssertEqual(row.course, "WRIT150")
        XCTAssertEqual(row.courseColor, .pink)
        XCTAssertEqual(row.dueText, DueLogic.relativeDueText(for: finished.dueDate, now: now, calendar: cal))
    }

    func test_doneRows_doNotCountTowardHiddenOpenWork() {
        let finished = (0..<5).map { done("D\($0)", completed: date(2026, 8, 26, $0, 0)) }

        let snap = snapshot(data(finished), limit: 3)

        XCTAssertTrue(snap.isEmpty)
        XCTAssertEqual(snap.doneRows.count, 3)
        XCTAssertEqual(snap.hiddenCount, 0)
    }

    // MARK: - Count caption (small widget, under the big number)

    func test_countCaption_saysOverdue_whenEverythingCountedIsLate() {
        let snap = snapshot(data([item("A", due: date(2026, 8, 24)), item("B", due: date(2026, 8, 26, 9, 0))]))
        XCTAssertEqual(snap.todayCount, 2)
        XCTAssertEqual(snap.countCaption, "overdue")
    }

    func test_countCaption_saysDueToday_whenNothingIsLate() {
        XCTAssertEqual(snapshot(data([item("A", due: date(2026, 8, 26, 17, 0))])).countCaption, "due today")
        XCTAssertEqual(snapshot(data([])).countCaption, "due today")
    }

    func test_countCaption_mixed_saysBoth() {
        let snap = snapshot(data([item("A", due: date(2026, 8, 24)), item("B", due: date(2026, 8, 26, 17, 0))]))
        XCTAssertEqual(snap.countCaption, "due or overdue")
    }
}
