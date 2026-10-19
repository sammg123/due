import XCTest
@testable import DueCore

final class WidgetTimelineTests: XCTestCase {
    private var cal: Calendar!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func data(_ items: [Assignment]) -> AppData {
        AppData(assignments: items, courseColors: [:], settings: DueSettings())
    }

    private func dates(_ items: [Assignment], from now: Date) -> [Date] {
        WidgetTimeline.entryDates(for: data(items), from: now, calendar: cal)
    }

    func test_startsNow_staysInsideTheHorizon_strictlyIncreasing() {
        let now = date(2026, 8, 26, 10, 0)

        let result = dates([], from: now)

        XCTAssertEqual(result.first, now)
        XCTAssertLessThanOrEqual(result.last!, now.addingTimeInterval(WidgetTimeline.horizon))
        XCTAssertEqual(result, result.sorted())
        XCTAssertEqual(Set(result).count, result.count)
    }

    func test_ticksEveryInterval_soMinuteAndHourTextStaysFresh() {
        let now = date(2026, 8, 26, 10, 0)

        let result = dates([], from: now)

        let expectedTicks = Int(WidgetTimeline.horizon / WidgetTimeline.tick)
        XCTAssertEqual(result.count, expectedTicks + 1)
        XCTAssertTrue(result.contains(now.addingTimeInterval(WidgetTimeline.tick)))
        XCTAssertTrue(result.contains(now.addingTimeInterval(WidgetTimeline.horizon)))
    }

    func test_includesTheExactMomentAnOpenItemFallsDue() {
        let now = date(2026, 8, 26, 10, 0)
        let dueAt = date(2026, 8, 26, 11, 37)

        let result = dates([Assignment(title: "Quiz", dueDate: dueAt)], from: now)

        XCTAssertTrue(result.contains(dueAt))
    }

    func test_ignoresDoneItems_pastDueDates_andDueDatesBeyondTheHorizon() {
        let now = date(2026, 8, 26, 10, 0)
        let doneDue = date(2026, 8, 26, 11, 37)
        let pastDue = date(2026, 8, 26, 9, 13)
        let farDue = date(2026, 8, 27, 11, 37)
        let items = [
            Assignment(title: "Done", dueDate: doneDue, isDone: true),
            Assignment(title: "Past", dueDate: pastDue),
            Assignment(title: "Far", dueDate: farDue),
        ]

        let result = dates(items, from: now)

        XCTAssertFalse(result.contains(doneDue))
        XCTAssertFalse(result.contains(pastDue))
        XCTAssertFalse(result.contains(farDue))
    }

    func test_includesMidnight_whenTheDayRollsOverInsideTheHorizon() {
        let now = date(2026, 8, 26, 22, 31)

        let result = dates([], from: now)

        XCTAssertTrue(result.contains(date(2026, 8, 27, 0, 0)))
    }
}
