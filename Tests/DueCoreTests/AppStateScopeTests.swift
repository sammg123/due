import XCTest
@testable import DueCore

@MainActor
final class AppStateScopeTests: XCTestCase {
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

    private func makeState(data: AppData = .empty) -> AppState {
        AppState(data: data, store: nil, now: now, calendar: cal)
    }

    // MARK: - weekLoad(offset:course:)

    func test_weekLoad_offsetCourse_narrowsCountsToThatCourse() {
        // Arrange
        let state = makeState()
        _ = state.add(title: "a", course: "CS225", dueDate: date(2026, 8, 27, 9, 0))
        _ = state.add(title: "b", course: "CS225", dueDate: date(2026, 8, 27, 20, 0))
        _ = state.add(title: "c", course: "MATH241", dueDate: date(2026, 8, 27, 10, 0))
        // Act
        let narrowed = state.weekLoad(offset: 0, course: "CS225")
        let all = state.weekLoad(offset: 0)
        // Assert (Aug 27 is index 4 in a Sunday-starting week containing Wed Aug 26)
        XCTAssertEqual(narrowed[4].count, 2)
        XCTAssertEqual(all[4].count, 3)
    }

    // MARK: - grouped(course:scope:)

    func test_grouped_courseAndDayScope_filterAcrossBuckets() {
        // Arrange
        let state = makeState()
        let a = state.add(title: "A", course: "CS225", dueDate: date(2026, 8, 28))! // soon
        let b = state.add(title: "B", course: "MATH241", dueDate: date(2026, 8, 28))! // soon, same day
        let c = state.add(title: "C", course: "CS225", dueDate: date(2026, 8, 30))! // thisWeek
        // Act
        let byCourse = state.grouped(course: "CS225", scope: .all)
        let byDay = state.grouped(course: nil, scope: .day(date(2026, 8, 28)))
        // Assert
        XCTAssertEqual(Set(byCourse.flatMap(\.items).map(\.id)), Set([a.id, c.id]))
        XCTAssertEqual(Set(byDay.flatMap(\.items).map(\.id)), Set([a.id, b.id]))
    }

    // MARK: - openCount(course:scope:)

    func test_openCount_courseAndScope_countsOnlyMatchingOpenItems() {
        // Arrange
        let state = makeState()
        let a = state.add(title: "A", course: "CS225", dueDate: date(2026, 8, 28))!
        _ = state.add(title: "B", course: "CS225", dueDate: date(2026, 8, 29))!
        _ = state.add(title: "C", course: "MATH241", dueDate: date(2026, 8, 28))!
        state.toggleDone(a.id)
        // Act / Assert
        XCTAssertEqual(state.openCount(course: "CS225", scope: .all), 1) // only the un-done CS225 item
        XCTAssertEqual(state.openCount(course: nil, scope: .day(date(2026, 8, 28))), 1) // A is done, only C remains
    }

    // MARK: - sortByCourse

    func test_sortByCourse_ordersAlphabeticallyNoCourseLast_dueDateWithinCourse_leavesOtherBucketsUntouched() {
        // Arrange: thisWeek bucket (4-6 days out from Aug 26)
        let state = makeState()
        let math = state.add(title: "math-hw", course: "MATH241", dueDate: date(2026, 8, 30))!
        let csLate = state.add(title: "cs-late", course: "CS225", dueDate: date(2026, 8, 31))!
        let csEarly = state.add(title: "cs-early", course: "CS225", dueDate: date(2026, 8, 30))!
        let none = state.add(title: "no-course", course: nil, dueDate: date(2026, 9, 1))!
        // soon bucket, added in this exact order; should be untouched by sorting thisWeek
        let s0 = state.add(title: "s0", course: nil, dueDate: date(2026, 8, 27))!
        let s1 = state.add(title: "s1", course: "CS225", dueDate: date(2026, 8, 28))!

        // Act
        state.sortByCourse(in: .thisWeek)

        // Assert
        let groups = state.grouped
        let thisWeek = groups.first { $0.bucket == .thisWeek }!
        let soon = groups.first { $0.bucket == .soon }!
        XCTAssertEqual(thisWeek.items.map(\.id), [csEarly.id, csLate.id, math.id, none.id])
        XCTAssertEqual(soon.items.map(\.id), [s0.id, s1.id])
    }

    // MARK: - DueSettings.smartParsing

    func test_dueSettings_decodesSmartParsingDefaultTrue_whenKeyMissing() throws {
        // Arrange
        let json = Data(#"{"soonDays":3,"weekDays":7,"launchAtLogin":false}"#.utf8)
        // Act
        let decoded = try JSONDecoder().decode(DueSettings.self, from: json)
        // Assert
        XCTAssertTrue(decoded.smartParsing)
    }

    func test_dueSettings_roundTripsSmartParsingFalse() throws {
        // Arrange
        let settings = DueSettings(smartParsing: false)
        // Act
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DueSettings.self, from: data)
        // Assert
        XCTAssertFalse(decoded.smartParsing)
    }
}
