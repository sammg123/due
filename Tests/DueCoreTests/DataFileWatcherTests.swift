import XCTest
@testable import DueCore

final class DataFileWatcherTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func test_firesWhenAnotherWriterReplacesTheFile() throws {
        // Arrange
        let url = tempRoot.appendingPathComponent("assignments.json")
        let fired = expectation(description: "change noticed")
        let watcher = DataFileWatcher(fileURL: url) { fired.fulfill() }

        // Act: an atomic save, exactly how the widget writes
        try JSONStore(url: url).save(.empty)

        // Assert
        wait(for: [fired], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    func test_collapsesABurstOfWritesIntoOneCallback() throws {
        let url = tempRoot.appendingPathComponent("assignments.json")
        var calls = 0
        let watcher = DataFileWatcher(fileURL: url) { calls += 1 }

        for i in 0..<3 {
            try JSONStore(url: url).save(AppData(assignments: [], courseColors: ["C\(i)": .blue], settings: DueSettings()))
        }
        let settled = expectation(description: "debounce window passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertEqual(calls, 1)
        withExtendedLifetime(watcher) {}
    }

    func test_createsAMissingFolderSoAFreshInstallCanBeWatched() {
        let url = tempRoot.appendingPathComponent("nested/assignments.json")
        let watcher = DataFileWatcher(fileURL: url) {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        XCTAssertTrue(watcher.isWatching)
    }
}
