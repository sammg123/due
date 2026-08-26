import XCTest
@testable import DueCore

/// `DueLogic.weekTitle`/`dayTitle` format with bare `DateFormatter()`s that resolve their time zone
/// from `NSTimeZone.default` at format time, not from the `calendar` parameter (see DueLogicTests for
/// the full explanation). Pin `NSTimeZone.default` for the duration of each test, same as DueLogicTests.
final class ScopeTests: XCTestCase {
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

    private func assignment(due: Date, isDone: Bool = false, title: String = "A") -> Assignment {
        Assignment(title: title, dueDate: due, isDone: isDone)
    }

    // MARK: - weekInterval(containing:)

    func test_weekInterval_sundayFirstWeekday_startsOnSunday() {
        // Arrange
        var c = cal!
        c.firstWeekday = 1
        // Act
        let interval = DueLogic.weekInterval(containing: now, calendar: c)
        // Assert
        XCTAssertEqual(interval.start, date(2026, 8, 23))
        XCTAssertEqual(interval.end, date(2026, 8, 30))
    }

    func test_weekInterval_mondayFirstWeekday_startsOnMonday() {
        var c = cal!
        c.firstWeekday = 2
        let interval = DueLogic.weekInterval(containing: now, calendar: c)
        XCTAssertEqual(interval.start, date(2026, 8, 24))
        XCTAssertEqual(interval.end, date(2026, 8, 31))
    }

    func test_weekInterval_offsetWeeks_shiftsByWholeWeeksAndStaysAligned() {
        var c = cal!
        c.firstWeekday = 1
        let plusOne = DueLogic.weekInterval(containing: now, offsetWeeks: 1, calendar: c)
        let minusOne = DueLogic.weekInterval(containing: now, offsetWeeks: -1, calendar: c)
        let plusThree = DueLogic.weekInterval(containing: now, offsetWeeks: 3, calendar: c)

        XCTAssertEqual(plusOne.start, date(2026, 8, 30))
        XCTAssertEqual(plusOne.end, date(2026, 9, 6))
        XCTAssertEqual(minusOne.start, date(2026, 8, 16))
        XCTAssertEqual(minusOne.end, date(2026, 8, 23))
        XCTAssertEqual(plusThree.start, date(2026, 9, 13))
        XCTAssertEqual(plusThree.end, date(2026, 9, 20))
    }

    // MARK: - weekLoad(items, week:)

    func test_weekLoad_returnsSevenDaysStartingAtWeekStart() {
        // Arrange
        let week = DueLogic.weekInterval(containing: now, calendar: cal)
        // Act
        let load = DueLogic.weekLoad([], week: week, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(load.count, 7)
        let expectedDates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: week.start)! }
        XCTAssertEqual(load.map(\.date), expectedDates)
    }

    func test_weekLoad_isTodayTrueOnlyForRealToday() {
        let week = DueLogic.weekInterval(containing: now, calendar: cal)
        let load = DueLogic.weekLoad([], week: week, now: now, calendar: cal)
        // Aug 23 (Sun) is index 0, so Aug 26 (Wed, "now") is index 3.
        XCTAssertTrue(load[3].isToday)
        XCTAssertEqual(load.filter(\.isToday).count, 1)
    }

    func test_weekLoad_countsOpenItemsDueOnEachDay() {
        let week = DueLogic.weekInterval(containing: now, calendar: cal)
        let items = [
            assignment(due: date(2026, 8, 27, 9, 0), title: "tomorrow-morning"),
            assignment(due: date(2026, 8, 27, 20, 0), title: "tomorrow-evening"),
            assignment(due: date(2026, 8, 29, 9, 0), title: "saturday"),
        ]
        let load = DueLogic.weekLoad(items, week: week, now: now, calendar: cal)
        XCTAssertEqual(load[0].count, 0)
        XCTAssertEqual(load[4].count, 2) // Aug 27
        XCTAssertEqual(load[6].count, 1) // Aug 29
    }

    func test_weekLoad_foldsOverdueIntoTodayOnly_whenTodayIsInTheWeek() {
        let week = DueLogic.weekInterval(containing: now, calendar: cal)
        let items = [
            assignment(due: date(2026, 8, 20, 9, 0), title: "overdue-from-days-ago"),
            assignment(due: date(2026, 8, 26, 20, 0), title: "due-later-today"),
        ]
        let load = DueLogic.weekLoad(items, week: week, now: now, calendar: cal)
        XCTAssertEqual(load[3].count, 2) // today's own item + the folded-in overdue item
    }

    func test_weekLoad_nextWeekStrip_doesNotFoldOverdueAnywhere() {
        // Arrange: an overdue item, but the strip is next week, which doesn't contain "today".
        let nextWeek = DueLogic.weekInterval(containing: now, offsetWeeks: 1, calendar: cal)
        let items = [assignment(due: date(2026, 8, 20, 9, 0), title: "overdue-from-days-ago")]
        // Act
        let load = DueLogic.weekLoad(items, week: nextWeek, now: now, calendar: cal)
        // Assert
        XCTAssertTrue(load.allSatisfy { $0.count == 0 })
        XCTAssertTrue(load.allSatisfy { !$0.isToday })
    }

    func test_weekLoad_ignoresDoneItems() {
        let week = DueLogic.weekInterval(containing: now, calendar: cal)
        let items = [assignment(due: date(2026, 8, 27, 9, 0), isDone: true, title: "done-tomorrow")]
        let load = DueLogic.weekLoad(items, week: week, now: now, calendar: cal)
        XCTAssertEqual(load[4].count, 0)
    }

    // MARK: - filter(course:scope:)

    func test_filter_scopeAll_narrowsByCourse_andKeepsAllWhenCourseIsNil() {
        // Arrange
        let a = assignment(due: date(2026, 8, 27), title: "cs")
        let b = assignment(due: date(2026, 8, 28), title: "math")
        let items = [a, b]
        // Act / Assert
        XCTAssertEqual(DueLogic.filter(items, course: nil, scope: .all, calendar: cal).count, 2)
    }

    func test_filter_scopeDay_matchesOnlyThatDay() {
        let items = [
            assignment(due: date(2026, 8, 27, 9, 0), title: "morning"),
            assignment(due: date(2026, 8, 27, 20, 0), title: "evening"),
            assignment(due: date(2026, 8, 28, 9, 0), title: "next-day"),
        ]
        let filtered = DueLogic.filter(items, course: nil, scope: .day(date(2026, 8, 27)), calendar: cal)
        XCTAssertEqual(filtered.map(\.title).sorted(), ["evening", "morning"])
    }

    func test_filter_scopeWeek_matchesWithinInterval() {
        let week = DueLogic.weekInterval(containing: now, calendar: cal) // Aug 23 - Aug 30
        let items = [
            assignment(due: date(2026, 8, 24), title: "inside"),
            assignment(due: date(2026, 9, 2), title: "outside"),
        ]
        let filtered = DueLogic.filter(items, course: nil, scope: .week(week), calendar: cal)
        XCTAssertEqual(filtered.map(\.title), ["inside"])
    }

    func test_filter_keepsDoneItems() {
        let items = [
            assignment(due: date(2026, 8, 27), isDone: true, title: "done"),
            assignment(due: date(2026, 8, 27), isDone: false, title: "open"),
        ]
        let filtered = DueLogic.filter(items, course: nil, scope: .day(date(2026, 8, 27)), calendar: cal)
        XCTAssertEqual(filtered.count, 2)
    }

    // MARK: - weekTitle

    func test_weekTitle_relativeLabels_thisNextLastWeek() {
        let thisWeek = DueLogic.weekInterval(containing: now, calendar: cal)
        let nextWeek = DueLogic.weekInterval(containing: now, offsetWeeks: 1, calendar: cal)
        let lastWeek = DueLogic.weekInterval(containing: now, offsetWeeks: -1, calendar: cal)

        XCTAssertEqual(DueLogic.weekTitle(thisWeek, now: now, calendar: cal), "This week")
        XCTAssertEqual(DueLogic.weekTitle(nextWeek, now: now, calendar: cal), "Next week")
        XCTAssertEqual(DueLogic.weekTitle(lastWeek, now: now, calendar: cal), "Last week")
    }

    func test_weekTitle_absoluteLabels_crossMonthAndSameMonth() {
        // A `now` far from either week so neither is labeled This/Next/Last.
        let farNow = date(2026, 1, 5)
        let crossMonthWeek = DateInterval(start: date(2026, 8, 31), duration: 7 * 86_400) // Aug 31 - Sep 6
        let sameMonthWeek = DateInterval(start: date(2026, 9, 7), duration: 7 * 86_400) // Sep 7 - Sep 13

        XCTAssertEqual(DueLogic.weekTitle(crossMonthWeek, now: farNow, calendar: cal), "Aug 31 to Sep 6")
        XCTAssertEqual(DueLogic.weekTitle(sameMonthWeek, now: farNow, calendar: cal), "Sep 7 to 13")
    }

    // MARK: - dayTitle

    func test_dayTitle_labelsForTodayTomorrowAndOtherDay() {
        XCTAssertEqual(DueLogic.dayTitle(date(2026, 8, 26, 15, 0), now: now, calendar: cal), "Today")
        XCTAssertEqual(DueLogic.dayTitle(date(2026, 8, 27, 9, 0), now: now, calendar: cal), "Tomorrow")
        XCTAssertEqual(DueLogic.dayTitle(date(2026, 8, 29), now: now, calendar: cal), "Sat, Aug 29")
    }
}
