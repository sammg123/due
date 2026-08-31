import XCTest
@testable import DueCore

final class NoteTests: XCTestCase {
    func testDisplayTitleUsesTitleWhenPresent() {
        let note = Note(title: "Lecture 4", body: "something")
        XCTAssertEqual(note.displayTitle, "Lecture 4")
    }

    func testDisplayTitleFallsBackToFirstBodyLine() {
        let note = Note(title: "", body: "\n\n  Thermodynamics intro  \nMore text")
        XCTAssertEqual(note.displayTitle, "Thermodynamics intro")
    }

    func testDisplayTitleUntitledWhenEmpty() {
        let note = Note(title: "   ", body: "  \n ")
        XCTAssertEqual(note.displayTitle, "Untitled")
    }

    func testDisplayTitleTruncatesLongBodyLine() {
        let long = String(repeating: "a", count: 200)
        let note = Note(title: "", body: long)
        XCTAssertLessThanOrEqual(note.displayTitle.count, Note.displayTitleMaxLength)
    }

    func testPreviewSkipsTitleLineAndCollapsesWhitespace() {
        let note = Note(title: "", body: "Heading line\n\nFirst real   content\nsecond line")
        XCTAssertEqual(note.preview, "First real content second line")
    }

    func testPreviewStripsMarkdownHeadingAndBulletMarkers() {
        let note = Note(title: "T", body: "## Summary\n\n- first point\n- second point")
        XCTAssertEqual(note.preview, "Summary first point second point")
    }

    func testPreviewStripsRichMarkersAndSkipsSeparatorLines() {
        let note = Note(title: "T", body: "> **IQR** is `Q3-Q1`\n---\n|---|---|")
        XCTAssertEqual(note.preview, "IQR is Q3-Q1")
    }

    func testTolerantDecodingFillsDefaults() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"T","body":"B","createdAt":"2026-08-30T10:00:00Z","updatedAt":"2026-08-30T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let note = try decoder.decode(Note.self, from: Data(json.utf8))
        XCTAssertNil(note.course)
        XCTAssertEqual(note.audioFiles, [])
        XCTAssertEqual(note.lectureSeconds, 0)
    }

    func testUpdatingBodyBumpsUpdatedAtAndKeepsCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        let note = Note(title: "T", body: "old", createdAt: created, updatedAt: created)
        let updated = note.updating(body: "new", at: later)
        XCTAssertEqual(updated.body, "new")
        XCTAssertEqual(updated.createdAt, created)
        XCTAssertEqual(updated.updatedAt, later)
        // Original untouched (immutability).
        XCTAssertEqual(note.body, "old")
    }

    func testWordCount() {
        XCTAssertEqual(Note(title: "", body: "").wordCount, 0)
        XCTAssertEqual(Note(title: "", body: "one two  three\nfour").wordCount, 4)
    }
}
