import XCTest
@testable import DueCore

final class JSONStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func makeCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    // MARK: - Round trip

    func test_saveThenLoad_roundTripsFullAppData() throws {
        // Arrange
        let cal = makeCalendar()
        let store = JSONStore(url: tempRoot.appendingPathComponent("assignments.json"))

        let withAllOptionals = Assignment(
            id: UUID(),
            title: "Essay",
            course: "CS225",
            dueDate: date(2026, 8, 28, 17, 0, calendar: cal),
            estimateMinutes: 90,
            notes: "Bring sources",
            isDone: true,
            completedAt: date(2026, 8, 27, 12, 0, calendar: cal),
            createdAt: date(2026, 8, 1, 9, 0, calendar: cal),
            sortOrder: 3
        )
        let withoutOptionals = Assignment(
            id: UUID(),
            title: "Reading",
            dueDate: date(2026, 8, 29, 23, 59, calendar: cal),
            createdAt: date(2026, 8, 2, 9, 0, calendar: cal),
            sortOrder: 0
        )
        let data = AppData(
            assignments: [withAllOptionals, withoutOptionals],
            courseColors: ["CS225": .blue, "MATH241": .purple],
            settings: DueSettings(soonDays: 2, weekDays: 5, launchAtLogin: true)
        )

        // Act
        try store.save(data)
        let loaded = try store.load()

        // Assert
        XCTAssertEqual(loaded, data)
    }

    // MARK: - Missing / corrupt file

    func test_load_missingFile_returnsEmpty() throws {
        let store = JSONStore(url: tempRoot.appendingPathComponent("does-not-exist.json"))
        let loaded = try store.load()
        XCTAssertEqual(loaded, .empty)
    }

    func test_load_garbageBytes_throws() throws {
        let url = tempRoot.appendingPathComponent("garbage.json")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("not json at all {{{".utf8).write(to: url)
        let store = JSONStore(url: url)
        XCTAssertThrowsError(try store.load())
    }

    // MARK: - save creates the directory

    func test_save_createsIntermediateDirectories() throws {
        let nestedURL = tempRoot
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("assignments.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedURL.deletingLastPathComponent().path))

        let store = JSONStore(url: nestedURL)
        try store.save(.empty)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: nestedURL.deletingLastPathComponent().path, isDirectory: &isDirectory)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedURL.path))
    }

    // MARK: - Tolerant decoding

    func test_load_minimalAssignmentJSON_fillsInDefaults() throws {
        let url = tempRoot.appendingPathComponent("minimal.json")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let json = """
        {"assignments":[{"id":"9B7F1C2A-1111-4E1B-9C3D-2C6E7F8A9B0C","title":"x","dueDate":"2026-08-26T23:59:00Z"}]}
        """
        try Data(json.utf8).write(to: url)

        let store = JSONStore(url: url)
        let loaded = try store.load()

        XCTAssertEqual(loaded.assignments.count, 1)
        let a = loaded.assignments[0]
        XCTAssertEqual(a.title, "x")
        XCTAssertNil(a.course)
        XCTAssertNil(a.estimateMinutes)
        XCTAssertNil(a.notes)
        XCTAssertFalse(a.isDone)
        XCTAssertNil(a.completedAt)
        XCTAssertEqual(a.sortOrder, 0)
        XCTAssertEqual(loaded.courseColors, [:])
        XCTAssertEqual(loaded.settings, DueSettings())
    }

    func test_load_emptyTopLevelObject_fillsInAllDefaults() throws {
        let url = tempRoot.appendingPathComponent("empty-object.json")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)

        let store = JSONStore(url: url)
        let loaded = try store.load()

        XCTAssertEqual(loaded, .empty)
    }
}
