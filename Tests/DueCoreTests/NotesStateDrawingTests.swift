import XCTest
@testable import DueCore

@MainActor
final class NotesStateDrawingTests: XCTestCase {
    private var tempRoot: URL!
    private var store: NotesStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("due-drawing-tests-\(UUID().uuidString)", isDirectory: true)
        store = NotesStore(directory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testAttachDrawingAddsMarkerFileAndRegistration() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateBody(note.id, body: "my notes")
        let drawing = try XCTUnwrap(state.attachDrawing(to: note.id))

        let body = state.note(note.id)?.body ?? ""
        XCTAssertTrue(body.contains("[drawing: \(drawing.id.uuidString)]"))
        XCTAssertEqual(state.note(note.id)?.drawingFiles, [NotesStore.drawingFileName(for: drawing.id)])
        XCTAssertNoThrow(try store.loadDrawing(id: drawing.id))
        // The body parses to a drawing block.
        let blocks = NoteMarkdown.blocks(body)
        XCTAssertTrue(blocks.contains(.drawing(id: drawing.id)))
    }

    func testUpdateDrawingPersistsAndCacheServesIt() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        let drawing = try XCTUnwrap(state.attachDrawing(to: note.id))
        let updated = drawing.updating(elements: [.text(x: 10, y: 10, string: "hi")])
        state.updateDrawing(updated, for: note.id)
        XCTAssertEqual(state.drawing(drawing.id)?.elements.count, 1)
        XCTAssertEqual(try store.loadDrawing(id: drawing.id).elements.count, 1)
    }

    func testDeleteDrawingRemovesMarkerFileAndRegistration() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        state.updateBody(note.id, body: "keep this text")
        let drawing = try XCTUnwrap(state.attachDrawing(to: note.id))
        state.deleteDrawing(drawing.id, from: note.id)

        let body = state.note(note.id)?.body ?? ""
        XCTAssertFalse(body.contains("[drawing:"))
        XCTAssertTrue(body.contains("keep this text"))
        XCTAssertEqual(state.note(note.id)?.drawingFiles, [])
        XCTAssertThrowsError(try store.loadDrawing(id: drawing.id))
    }

    func testAIDrawingBackupAndRevert() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        let drawing = try XCTUnwrap(state.attachDrawing(to: note.id))
        state.applyAIDrawing(drawing.id, elements: [.text(x: 1, y: 1, string: "ai")], for: note.id)
        XCTAssertEqual(state.drawing(drawing.id)?.elements.first?.text, "ai")
        XCTAssertNotNil(state.drawingAIBackup(drawing.id))
        state.revertAIDrawing(drawing.id, for: note.id)
        XCTAssertEqual(state.drawing(drawing.id)?.elements.count, 0)
        XCTAssertNil(state.drawingAIBackup(drawing.id))
    }

    func testDeletingNoteRemovesItsDrawingFiles() throws {
        let state = NotesState(store: store)
        let note = state.createNote(course: nil)
        let drawing = try XCTUnwrap(state.attachDrawing(to: note.id))
        state.deleteNote(note.id)
        XCTAssertThrowsError(try store.loadDrawing(id: drawing.id))
    }

    func testDrawingMarkerParsing() {
        let id = UUID()
        XCTAssertEqual(NoteMarkdown.blocks("[drawing: \(id.uuidString)]"), [.drawing(id: id)])
        XCTAssertEqual(NoteMarkdown.blocks("[drawing: not-a-uuid]").first.map(isParagraph), true)
    }

    private func isParagraph(_ block: NoteBlock) -> Bool {
        if case .paragraph = block { return true }
        return false
    }

    func testPreviewSkipsDrawingMarkers() {
        let note = Note(title: "T", body: "[drawing: \(UUID().uuidString)]\nreal text")
        XCTAssertEqual(note.preview, "real text")
    }
}
