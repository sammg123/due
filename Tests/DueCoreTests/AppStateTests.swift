import XCTest
@testable import DueCore

@MainActor
final class AppStateTests: XCTestCase {
    private var cal: Calendar!
    private var now: Date!
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
        now = date(2026, 8, 26, 10, 0) // Wednesday
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func makeState(data: AppData = .empty, store: JSONStore? = nil) -> AppState {
        AppState(data: data, store: store, now: now, calendar: cal)
    }

    /// `createdAt`/`completedAt` are stamped with the real wall clock by production code and lose
    /// sub-second precision through JSONStore's ISO8601 (no-fractional-seconds) encoding, so a
    /// disk round trip can't be compared with strict Date equality. Everything else can.
    private func assertPersisted(_ store: JSONStore, matches state: AppState, file: StaticString = #filePath, line: UInt = #line) throws {
        let loaded = try store.load()
        let onDisk = loaded.assignments.sorted { $0.sortOrder < $1.sortOrder }
        let inMemory = state.data.assignments.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(onDisk.map(\.id), inMemory.map(\.id), file: file, line: line)
        for (persisted, live) in zip(onDisk, inMemory) {
            XCTAssertEqual(persisted.title, live.title, file: file, line: line)
            XCTAssertEqual(persisted.course, live.course, file: file, line: line)
            XCTAssertEqual(persisted.dueDate, live.dueDate, file: file, line: line)
            XCTAssertEqual(persisted.isDone, live.isDone, file: file, line: line)
            XCTAssertEqual(persisted.sortOrder, live.sortOrder, file: file, line: line)
            XCTAssertEqual((persisted.completedAt ?? .distantPast).timeIntervalSince(live.completedAt ?? .distantPast), 0, accuracy: 1.0, file: file, line: line)
            XCTAssertEqual(persisted.createdAt.timeIntervalSince(live.createdAt), 0, accuracy: 1.0, file: file, line: line)
        }
        XCTAssertEqual(loaded.courseColors, state.data.courseColors, file: file, line: line)
        XCTAssertEqual(loaded.settings, state.data.settings, file: file, line: line)
    }

    // MARK: - add

    func test_add_trimsTitleWhitespace() {
        // Arrange
        let state = makeState()
        // Act
        let item = state.add(title: "  Homework  ", course: nil, dueDate: date(2026, 8, 28))
        // Assert
        XCTAssertEqual(item?.title, "Homework")
        XCTAssertEqual(state.assignments.count, 1)
    }

    func test_add_rejectsBlankTitle() {
        let state = makeState()
        let item = state.add(title: "   ", course: nil, dueDate: date(2026, 8, 28))
        XCTAssertNil(item)
        XCTAssertEqual(state.assignments.count, 0)
    }

    func test_add_assignsIncreasingSortOrder() {
        let state = makeState()
        let a = state.add(title: "A", course: nil, dueDate: date(2026, 8, 28))!
        let b = state.add(title: "B", course: nil, dueDate: date(2026, 8, 28))!
        let c = state.add(title: "C", course: nil, dueDate: date(2026, 8, 28))!
        XCTAssertEqual([a.sortOrder, b.sortOrder, c.sortOrder], [0, 1, 2])
    }

    func test_add_autoAssignsCourseColor_fromRotation_forNewCourse() {
        let state = makeState()
        _ = state.add(title: "A", course: "CS225", dueDate: date(2026, 8, 28))
        XCTAssertEqual(state.color(forCourse: "CS225"), PaletteColor.courseRotation[0])
    }

    func test_add_keepsSameCourseColor_forRepeatCourse() {
        let state = makeState()
        _ = state.add(title: "A", course: "CS225", dueDate: date(2026, 8, 28))
        let firstColor = state.color(forCourse: "CS225")
        _ = state.add(title: "B", course: "CS225", dueDate: date(2026, 8, 29))
        XCTAssertEqual(state.color(forCourse: "CS225"), firstColor)
    }

    func test_add_secondDistinctCourse_getsNextRotationColor() {
        let state = makeState()
        _ = state.add(title: "A", course: "CS225", dueDate: date(2026, 8, 28))
        _ = state.add(title: "B", course: "MATH241", dueDate: date(2026, 8, 29))
        XCTAssertEqual(state.color(forCourse: "MATH241"), PaletteColor.courseRotation[1])
    }

    // MARK: - addQuick

    func test_addQuick_usesParsedDateOverFallback() {
        let state = makeState()
        let fallback = date(2030, 1, 1)
        let item = state.addQuick("essay due tomorrow", fallbackDue: fallback)
        XCTAssertEqual(item?.dueDate, date(2026, 8, 27, 23, 59))
    }

    func test_addQuick_usesFallback_whenNoDateParsed() {
        let state = makeState()
        let fallback = date(2030, 1, 1)
        let item = state.addQuick("lab report", fallbackDue: fallback)
        XCTAssertEqual(item?.dueDate, fallback)
    }

    func test_addQuick_explicitCourseAndEstimate_overrideParsedValues() {
        let state = makeState()
        let item = state.addQuick("task #CS225 ~30m", fallbackDue: date(2026, 9, 1), course: "OVERRIDE", estimateMinutes: 99)
        XCTAssertEqual(item?.course, "OVERRIDE")
        XCTAssertEqual(item?.estimateMinutes, 99)
    }

    // MARK: - toggleDone

    func test_toggleDone_setsCompletedAt() {
        let state = makeState()
        let item = state.add(title: "A", course: nil, dueDate: date(2026, 8, 28))!
        state.toggleDone(item.id)
        let updated = state.assignments.first { $0.id == item.id }!
        XCTAssertTrue(updated.isDone)
        XCTAssertNotNil(updated.completedAt)
    }

    func test_toggleDone_twice_clearsCompletedAt() {
        let state = makeState()
        let item = state.add(title: "A", course: nil, dueDate: date(2026, 8, 28))!
        state.toggleDone(item.id)
        state.toggleDone(item.id)
        let updated = state.assignments.first { $0.id == item.id }!
        XCTAssertFalse(updated.isDone)
        XCTAssertNil(updated.completedAt)
    }

    // MARK: - delete / clearCompleted

    func test_delete_removesOnlyTheTargetedItem() {
        let state = makeState()
        let a = state.add(title: "A", course: nil, dueDate: date(2026, 8, 28))!
        let b = state.add(title: "B", course: nil, dueDate: date(2026, 8, 28))!
        state.delete(a.id)
        XCTAssertEqual(state.assignments.map(\.id), [b.id])
    }

    func test_clearCompleted_removesOnlyDoneItems() {
        let state = makeState()
        let a = state.add(title: "A", course: nil, dueDate: date(2026, 8, 28))!
        let b = state.add(title: "B", course: nil, dueDate: date(2026, 8, 28))!
        state.toggleDone(a.id)
        state.clearCompleted()
        XCTAssertEqual(state.assignments.map(\.id), [b.id])
    }

    // MARK: - courses

    func test_courses_listsDistinctNamesMostRecentFirst() {
        let state = makeState()
        var a = state.add(title: "HW1", course: "CS225", dueDate: date(2026, 8, 28))!
        var b = state.add(title: "HW2", course: "MATH241", dueDate: date(2026, 8, 28))!
        var c = state.add(title: "HW3", course: "CS225", dueDate: date(2026, 8, 28))!
        // `add` stamps createdAt with the real wall clock; pin deterministic values via `update`
        // so "most recent first" isn't a race against how fast the test runs.
        a.createdAt = date(2026, 1, 1)
        b.createdAt = date(2026, 1, 2)
        c.createdAt = date(2026, 1, 3)
        state.update(a)
        state.update(b)
        state.update(c)
        XCTAssertEqual(state.courses, ["CS225", "MATH241"])
    }

    // MARK: - move

    func test_move_reordersWithinBucket_leavesOtherBucketsUntouched() {
        let state = makeState()
        // thisWeek bucket: 3 items, 4-6 days out
        _ = state.add(title: "w0", course: nil, dueDate: date(2026, 8, 30))!
        _ = state.add(title: "w1", course: nil, dueDate: date(2026, 8, 31))!
        _ = state.add(title: "w2", course: nil, dueDate: date(2026, 9, 1))!
        // soon bucket: 2 items, 1-2 days out
        let s0 = state.add(title: "s0", course: nil, dueDate: date(2026, 8, 27))!
        let s1 = state.add(title: "s1", course: nil, dueDate: date(2026, 8, 28))!

        state.move(in: .thisWeek, fromOffsets: [0], toOffset: 2)

        let groups = state.grouped
        let thisWeek = groups.first { $0.bucket == .thisWeek }!
        let soon = groups.first { $0.bucket == .soon }!

        XCTAssertEqual(thisWeek.items.map(\.title), ["w1", "w0", "w2"])
        XCTAssertEqual(soon.items.map(\.id), [s0.id, s1.id])
    }

    func test_move_inDoneBucket_isNoOp() {
        let state = makeState()
        let a = state.add(title: "A", course: nil, dueDate: date(2026, 8, 20))!
        let b = state.add(title: "B", course: nil, dueDate: date(2026, 8, 21))!
        state.toggleDone(a.id)
        state.toggleDone(b.id)
        let before = state.data
        state.move(in: .done, fromOffsets: [0], toOffset: 1)
        XCTAssertEqual(state.data, before)
    }

    // MARK: - sortByDueDate

    func test_sortByDueDate_resetsBucketToChronologicalOrder() {
        let state = makeState()
        // Added out of due-date order; sortOrder still follows insertion order.
        _ = state.add(title: "latest", course: nil, dueDate: date(2026, 9, 2))!
        _ = state.add(title: "middle", course: nil, dueDate: date(2026, 8, 31))!
        _ = state.add(title: "earliest", course: nil, dueDate: date(2026, 8, 30))!

        let beforeSort = state.grouped.first { $0.bucket == .thisWeek }!
        XCTAssertEqual(beforeSort.items.map(\.title), ["latest", "middle", "earliest"])

        state.sortByDueDate(in: .thisWeek)

        let afterSort = state.grouped.first { $0.bucket == .thisWeek }!
        XCTAssertEqual(afterSort.items.map(\.title), ["earliest", "middle", "latest"])
    }

    // MARK: - updateSettings

    func test_updateSettings_changesStoredSettingsAndDerivedBuckets() {
        let state = makeState()
        let item = state.add(title: "A", course: nil, dueDate: date(2026, 8, 29))! // 3 days out: soon by default
        XCTAssertEqual(state.bucket(for: item), .soon)

        state.updateSettings(DueSettings(soonDays: 1, weekDays: 7))

        XCTAssertEqual(state.settings, DueSettings(soonDays: 1, weekDays: 7))
        let updated = state.assignments.first { $0.id == item.id }!
        XCTAssertEqual(state.bucket(for: updated), .thisWeek)
    }

    // MARK: - setColor

    func test_setColor_assignsColorEvenWithoutExistingAssignment() {
        let state = makeState()
        state.setColor(.pink, forCourse: "PHYS100")
        XCTAssertEqual(state.color(forCourse: "PHYS100"), .pink)
    }

    func test_setColor_overridesAutoAssignedColor() {
        let state = makeState()
        _ = state.add(title: "A", course: "CS225", dueDate: date(2026, 8, 28))
        state.setColor(.red, forCourse: "CS225")
        XCTAssertEqual(state.color(forCourse: "CS225"), .red)
    }

    // MARK: - refreshNow

    func test_refreshNow_movesItemFromTodayToOverdue() {
        let state = makeState()
        let item = state.add(title: "A", course: nil, dueDate: date(2026, 8, 26, 10, 30))! // 30 min after `now`
        XCTAssertEqual(state.bucket(for: item), .today)

        state.refreshNow(date(2026, 8, 26, 11, 0)) // an hour later, past the due time

        let updated = state.assignments.first { $0.id == item.id }!
        XCTAssertEqual(state.bucket(for: updated), .overdue)
    }

    // MARK: - Persistence

    func test_mutations_persistToDisk_andAreVisibleOnReload() throws {
        let store = JSONStore(url: tempRoot.appendingPathComponent("assignments.json"))
        let state = makeState(store: store)

        let item = state.add(title: "Essay", course: "CS225", dueDate: date(2026, 8, 28))!
        try assertPersisted(store, matches: state)

        state.toggleDone(item.id)
        try assertPersisted(store, matches: state)

        state.setColor(.red, forCourse: "CS225")
        try assertPersisted(store, matches: state)

        state.updateSettings(DueSettings(soonDays: 2, weekDays: 6))
        try assertPersisted(store, matches: state)

        state.delete(item.id)
        try assertPersisted(store, matches: state)

        // A fresh AppState reading the same store sees the persisted result.
        let reloaded = AppState(data: try store.load(), store: store, now: now, calendar: cal)
        XCTAssertEqual(reloaded.data.assignments.count, state.data.assignments.count)
        XCTAssertEqual(reloaded.data.settings, state.data.settings)
        XCTAssertEqual(reloaded.data.courseColors, state.data.courseColors)
    }
}

// MARK: - registered courses

@MainActor
final class AppStateCourseRegistryTests: XCTestCase {
    func test_registerCourse_appearsInCoursesAndGetsColorBeforeAnyAssignmentUsesIt() {
        // Arrange
        let state = AppState()

        // Act
        let name = state.registerCourse("  CS 225  ")

        // Assert
        XCTAssertEqual(name, "CS 225")
        XCTAssertEqual(state.courses, ["CS 225"])
        XCTAssertTrue(PaletteColor.courseRotation.contains(state.color(forCourse: "CS 225")))
        XCTAssertFalse(state.isCourseInUse("CS 225"))
    }

    func test_registerCourse_blankIsRejectedAndDuplicateKeepsExistingColor() {
        // Arrange
        let state = AppState()
        state.registerCourse("BIO 101")
        state.setColor(.pink, forCourse: "BIO 101")

        // Act
        let blank = state.registerCourse("   ")
        let again = state.registerCourse("BIO 101")

        // Assert
        XCTAssertNil(blank)
        XCTAssertEqual(again, "BIO 101")
        XCTAssertEqual(state.color(forCourse: "BIO 101"), .pink)
        XCTAssertEqual(state.courses, ["BIO 101"])
    }

    func test_courses_listsUsedCoursesFirstThenUnusedAlphabetically() {
        // Arrange
        let state = AppState()
        state.registerCourse("ZOO 100")
        state.registerCourse("ART 110")
        state.add(title: "Essay", course: "ENGL 200", dueDate: Date().addingTimeInterval(3600))

        // Act
        let courses = state.courses

        // Assert
        XCTAssertEqual(courses, ["ENGL 200", "ART 110", "ZOO 100"])
    }

    func test_removeCourse_onlyRemovesUnusedCourses() {
        // Arrange
        let state = AppState()
        state.registerCourse("UNUSED")
        state.add(title: "Lab", course: "USED", dueDate: Date().addingTimeInterval(3600))

        // Act
        let removedUnused = state.removeCourse("UNUSED")
        let removedUsed = state.removeCourse("USED")

        // Assert
        XCTAssertTrue(removedUnused)
        XCTAssertFalse(removedUsed)
        XCTAssertEqual(state.courses, ["USED"])
        XCTAssertEqual(state.color(forCourse: "UNUSED"), .gray)
    }

    func test_registerCourse_persistsToDisk() throws {
        // Arrange
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("due-courses-\(UUID().uuidString).json")
        let store = JSONStore(url: url)
        let state = AppState(store: store)

        // Act
        state.registerCourse("PHYS 211")

        // Assert
        let reloaded = AppState(data: try store.load(), store: store)
        XCTAssertEqual(reloaded.courses, ["PHYS 211"])
        try? FileManager.default.removeItem(at: url)
    }
}
