import XCTest
@testable import DueCore

@MainActor
final class NotesStateTests: XCTestCase {
    private var tempRoot: URL!
    private var store: NotesStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("due-notes-state-\(UUID().uuidString)", isDirectory: true)
        store = NotesStore(directory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testCreateNotePersistsAndSelects() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: "Math")
        XCTAssertEqual(state.notes.count, 1)
        XCTAssertEqual(state.selectedNoteID, note.id)
        XCTAssertEqual(try store.loadAll().notes.count, 1)
    }

    func testUpdateBodyIsVisibleImmediatelyAndPersistsAfterFlush() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateBody(note.id, body: "typed text")
        XCTAssertEqual(state.note(note.id)?.body, "typed text")
        // Debounced: not necessarily on disk yet; flush forces it.
        state.flushPendingSaves()
        XCTAssertEqual(try store.loadAll().notes.first?.body, "typed text")
    }

    func testUpdateTitleAndCoursePersist() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateTitle(note.id, title: "Renamed")
        state.updateCourse(note.id, course: "Bio")
        state.flushPendingSaves()
        let loaded = try store.loadAll().notes.first
        XCTAssertEqual(loaded?.title, "Renamed")
        XCTAssertEqual(loaded?.course, "Bio")
    }

    func testDeleteRemovesNoteAndClearsSelection() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.deleteNote(note.id)
        XCTAssertEqual(state.notes, [])
        XCTAssertNil(state.selectedNoteID)
        XCTAssertEqual(try store.loadAll().notes, [])
    }

    func testAppendTranscriptAddsHeadingOnceAndAppendsText() {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateBody(note.id, body: "my typed notes")
        state.appendTranscript(note.id, text: "first chunk.", sessionHeading: "Lecture · Aug 31")
        state.appendTranscript(note.id, text: "second chunk.", sessionHeading: "Lecture · Aug 31")
        let body = state.note(note.id)?.body ?? ""
        XCTAssertTrue(body.hasPrefix("my typed notes"))
        XCTAssertEqual(body.components(separatedBy: "Lecture · Aug 31").count, 2, "heading appears exactly once")
        XCTAssertTrue(body.contains("first chunk. second chunk."))
    }

    func testRecordAudioFileAppendsRelativeNameAndSeconds() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.recordAudioFile(note.id, fileName: "abc.m4a", seconds: 90)
        state.recordAudioFile(note.id, fileName: "def.m4a", seconds: 30)
        state.flushPendingSaves()
        let loaded = try store.loadAll().notes.first
        XCTAssertEqual(loaded?.audioFiles, ["abc.m4a", "def.m4a"])
        XCTAssertEqual(loaded?.lectureSeconds, 120)
    }

    func testAIEditKeepsBackupAndRevertRestoresIt() {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateBody(note.id, body: "raw messy notes")
        state.applyAIEdit(note.id, body: "Polished notes.")
        XCTAssertEqual(state.note(note.id)?.body, "Polished notes.")
        XCTAssertEqual(state.aiBackup(note.id), "raw messy notes")
        state.revertAIEdit(note.id)
        XCTAssertEqual(state.note(note.id)?.body, "raw messy notes")
        XCTAssertNil(state.aiBackup(note.id))
    }

    func testTypingAfterAIEditClearsBackup() {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateBody(note.id, body: "original")
        state.applyAIEdit(note.id, body: "polished")
        state.updateBody(note.id, body: "polished plus my typing")
        XCTAssertNil(state.aiBackup(note.id), "revert after typing would destroy the typing")
        state.revertAIEdit(note.id)
        XCTAssertEqual(state.note(note.id)?.body, "polished plus my typing")
    }

    func testUpdatingAddingAudioFileIsImmutable() {
        let note = Note(title: "T", body: "")
        let updated = note.updating(addingAudioFile: "a.m4a", seconds: 60)
        XCTAssertEqual(updated.audioFiles, ["a.m4a"])
        XCTAssertEqual(updated.lectureSeconds, 60)
        XCTAssertEqual(note.audioFiles, [])
    }

    func testLoadReportsSkippedFilesAsError() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: tempRoot.appendingPathComponent("bad.json"))
        let state = NotesState.load(store: store)
        XCTAssertNotNil(state.lastError)
        XCTAssertTrue(state.lastError?.contains("bad.json") ?? false)
    }
}
