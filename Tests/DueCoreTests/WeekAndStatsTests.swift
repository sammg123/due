import XCTest
@testable import DueCore

final class WeekAndStatsTests: XCTestCase {
    private var cal: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
        now = date(2026, 8, 26, 10, 0) // Wednesday
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func assignment(
        due: Date,
        isDone: Bool = false,
        completedAt: Date? = nil,
        title: String = "A"
    ) -> Assignment {
        Assignment(title: title, dueDate: due, isDone: isDone, completedAt: completedAt)
    }

    // MARK: - weekLoad

    func test_weekLoad_returnsSevenDaysStartingToday() {
        // Arrange / Act
        let load = DueLogic.weekLoad([], now: now, calendar: cal)
        // Assert
        XCTAssertEqual(load.count, 7)
        XCTAssertEqual(cal.startOfDay(for: load[0].date), cal.startOfDay(for: now))
    }

    func test_weekLoad_isTodayTrueOnlyForFirstDay() {
        let load = DueLogic.weekLoad([], now: now, calendar: cal)
        XCTAssertTrue(load[0].isToday)
        XCTAssertTrue(load.dropFirst().allSatisfy { !$0.isToday })
    }

    func test_weekLoad_countsOpenItemsDueOnEachDay() {
        let items = [
            assignment(due: date(2026, 8, 27, 9, 0), title: "tomorrow-morning"),
            assignment(due: date(2026, 8, 27, 20, 0), title: "tomorrow-evening"),
            assignment(due: date(2026, 8, 29, 9, 0), title: "three-days-out"),
        ]
        let load = DueLogic.weekLoad(items, now: now, calendar: cal)
        XCTAssertEqual(load[0].count, 0)
        XCTAssertEqual(load[1].count, 2) // tomorrow
        XCTAssertEqual(load[3].count, 1) // three days out
    }

    func test_weekLoad_foldsPastDueItemsIntoTodayCount() {
        let items = [
            assignment(due: date(2026, 8, 24, 9, 0), title: "overdue-from-two-days-ago"),
            assignment(due: date(2026, 8, 26, 20, 0), title: "due-later-today"),
        ]
        let load = DueLogic.weekLoad(items, now: now, calendar: cal)
        XCTAssertEqual(load[0].count, 2)
    }

    func test_weekLoad_ignoresDoneItems() {
        let items = [assignment(due: date(2026, 8, 27, 9, 0), isDone: true, title: "done-tomorrow")]
        let load = DueLogic.weekLoad(items, now: now, calendar: cal)
        XCTAssertEqual(load[1].count, 0)
    }

    // MARK: - doneStats

    func test_doneStats_completedThisWeek_usesCalendarWeekContainingNow() {
        // now's calendar week is Sun Aug 23 - Sat Aug 29, 2026.
        let withinWeek = assignment(due: date(2026, 8, 20), isDone: true, completedAt: date(2026, 8, 24, 9, 0), title: "within")
        let outsideWeek = assignment(due: date(2026, 8, 20), isDone: true, completedAt: date(2026, 9, 2, 9, 0), title: "outside")
        let stats = DueLogic.doneStats([withinWeek, outsideWeek], now: now, calendar: cal)
        XCTAssertEqual(stats.completedThisWeek, 1)
    }

    func test_doneStats_onTime_whenCompletedAtOrBeforeDueDate() {
        let onTime = assignment(due: date(2026, 8, 20, 17, 0), isDone: true, completedAt: date(2026, 8, 20, 16, 0))
        let stats = DueLogic.doneStats([onTime], now: now, calendar: cal)
        XCTAssertEqual(stats.onTimeCount, 1)
        XCTAssertEqual(stats.lateCount, 0)
    }

    func test_doneStats_late_whenCompletedAfterDueDate() {
        let late = assignment(due: date(2026, 8, 20, 17, 0), isDone: true, completedAt: date(2026, 8, 20, 18, 0))
        let stats = DueLogic.doneStats([late], now: now, calendar: cal)
        XCTAssertEqual(stats.onTimeCount, 0)
        XCTAssertEqual(stats.lateCount, 1)
    }

    func test_doneStats_onTimeRate_nilWhenNoDoneItems() {
        let stats = DueLogic.doneStats([], now: now, calendar: cal)
        XCTAssertNil(stats.onTimeRate)
    }

    func test_doneStats_onTimeRate_isHalf_withOneOnTimeAndOneLate() {
        let onTime = assignment(due: date(2026, 8, 20, 17, 0), isDone: true, completedAt: date(2026, 8, 20, 16, 0))
        let late = assignment(due: date(2026, 8, 21, 17, 0), isDone: true, completedAt: date(2026, 8, 21, 18, 0))
        let stats = DueLogic.doneStats([onTime, late], now: now, calendar: cal)
        XCTAssertEqual(stats.onTimeRate, 0.5)
    }

    // MARK: - WeekDay.weekdayLetter

    func test_weekdayLetter_isExactlyOneCharacter() {
        let wd = WeekDay(date: now, count: 0, isToday: true)
        XCTAssertEqual(wd.weekdayLetter.count, 1)
    }
}
