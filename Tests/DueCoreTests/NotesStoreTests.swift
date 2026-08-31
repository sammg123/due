import XCTest
@testable import DueCore

final class NotesStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var store: NotesStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("due-notes-tests-\(UUID().uuidString)", isDirectory: true)
        store = NotesStore(directory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testLoadAllOnMissingDirectoryIsEmpty() throws {
        let result = try store.loadAll()
        XCTAssertEqual(result.notes, [])
        XCTAssertEqual(result.skippedFiles, [])
    }

    /// ISO8601 persistence is whole-second, so round-trip tests use whole-second dates.
    private let fixedDate = Date(timeIntervalSince1970: 1_756_600_000)

    func testSaveThenLoadRoundTrips() throws {
        let note = Note(title: "Lecture", course: "Math", body: "hello world", createdAt: fixedDate, updatedAt: fixedDate)
        try store.save(note)
        let result = try store.loadAll()
        XCTAssertEqual(result.notes, [note])
    }

    func testSaveOverwritesSameNote() throws {
        let note = Note(title: "v1", body: "a")
        try store.save(note)
        try store.save(note.updating(body: "b", at: Date()))
        let result = try store.loadAll()
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].body, "b")
    }

    func testDeleteRemovesFile() throws {
        let note = Note(title: "gone", body: "")
        try store.save(note)
        try store.delete(note.id)
        XCTAssertEqual(try store.loadAll().notes, [])
    }

    func testCorruptFileIsSkippedAndReportedOthersLoad() throws {
        let good = Note(title: "good", body: "", createdAt: fixedDate, updatedAt: fixedDate)
        try store.save(good)
        let badURL = tempRoot.appendingPathComponent("nonsense.json")
        try Data("not json".utf8).write(to: badURL)
        let result = try store.loadAll()
        XCTAssertEqual(result.notes, [good])
        XCTAssertEqual(result.skippedFiles, ["nonsense.json"])
        // The corrupt file is left on disk, never silently deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: badURL.path))
    }

    func testNonJSONFilesAreIgnoredSilently() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: tempRoot.appendingPathComponent("rec.m4a"))
        let result = try store.loadAll()
        XCTAssertEqual(result.notes, [])
        XCTAssertEqual(result.skippedFiles, [])
    }

    func testUnsafeAudioFileNamesAreRejected() {
        XCTAssertTrue(NotesStore.isSafeAudioFileName("abc-1.m4a"))
        XCTAssertFalse(NotesStore.isSafeAudioFileName("../outside.m4a"))
        XCTAssertFalse(NotesStore.isSafeAudioFileName("a/b.m4a"))
        XCTAssertFalse(NotesStore.isSafeAudioFileName(".."))
        XCTAssertFalse(NotesStore.isSafeAudioFileName(""))
    }

    func testDeleteIgnoresTraversalAudioNames() throws {
        // A tampered note listing a path outside Audio/ must not delete that file.
        let outside = tempRoot.appendingPathComponent("victim.txt")
        try FileManager.default.createDirectory(at: store.audioDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: outside)
        var note = Note(title: "evil", body: "")
        note.audioFiles = ["../victim.txt"]
        try store.save(note)
        try store.delete(note.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testAudioDirectoryLivesUnderNotesDirectory() {
        XCTAssertEqual(store.audioDirectory.lastPathComponent, "Audio")
        XCTAssertEqual(store.audioDirectory.deletingLastPathComponent(), tempRoot)
    }

    func testDeleteRemovesNoteAudioFiles() throws {
        var note = Note(title: "with audio", body: "")
        try FileManager.default.createDirectory(at: store.audioDirectory, withIntermediateDirectories: true)
        let audioName = "\(note.id.uuidString)-1.m4a"
        let audioURL = store.audioDirectory.appendingPathComponent(audioName)
        try Data("fake".utf8).write(to: audioURL)
        note.audioFiles = [audioName]
        try store.save(note)

        try store.delete(note.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }
}
