import XCTest
@testable import DueCore

final class NoteMarkdownTests: XCTestCase {
    private func plain(_ text: String) -> [NoteInlineRun] { [NoteInlineRun(text: text, style: .plain)] }

    func testHeadingLevels() {
        XCTAssertEqual(NoteMarkdown.blocks("## Outliers"), [.heading(level: 2, runs: plain("Outliers"))])
        XCTAssertEqual(NoteMarkdown.blocks("### Sub"), [.heading(level: 3, runs: plain("Sub"))])
        XCTAssertEqual(NoteMarkdown.blocks("# Top"), [.heading(level: 1, runs: plain("Top"))])
    }

    func testBulletsWithNesting() {
        let blocks = NoteMarkdown.blocks("- first\n  - nested\n- second")
        XCTAssertEqual(blocks, [
            .bullet(indent: 0, runs: plain("first")),
            .bullet(indent: 1, runs: plain("nested")),
            .bullet(indent: 0, runs: plain("second")),
        ])
    }

    func testNumberedList() {
        let blocks = NoteMarkdown.blocks("1. alpha\n2. beta")
        XCTAssertEqual(blocks, [
            .numbered(number: 1, indent: 0, runs: plain("alpha")),
            .numbered(number: 2, indent: 0, runs: plain("beta")),
        ])
    }

    func testCalloutDividerAndFlow() {
        let blocks = NoteMarkdown.blocks("> remember this\n---\nflow: collect data -> clean -> model")
        XCTAssertEqual(blocks, [
            .callout(runs: plain("remember this")),
            .divider,
            .flow(steps: ["collect data", "clean", "model"]),
        ])
    }

    func testTableWithSeparatorRow() {
        let text = "| term | meaning |\n|---|---|\n| IQR | spread |\n| SD | sigma |"
        XCTAssertEqual(NoteMarkdown.blocks(text), [
            .table(header: ["term", "meaning"], rows: [["IQR", "spread"], ["SD", "sigma"]]),
        ])
    }

    func testPlainIndentedLinesKeepTheirIndent() {
        let blocks = NoteMarkdown.blocks("Outliers\n    Values outside range")
        XCTAssertEqual(blocks, [
            .paragraph(indent: 0, runs: plain("Outliers")),
            .paragraph(indent: 1, runs: plain("Values outside range")),
        ])
    }

    func testBlankLinesAreDropped() {
        XCTAssertEqual(NoteMarkdown.blocks("a\n\n\nb").count, 2)
    }

    func testInlineBoldItalicCode() {
        let runs = NoteMarkdown.runs("**IQR** is *spread* via `Q3-Q1` done")
        XCTAssertEqual(runs, [
            NoteInlineRun(text: "IQR", style: .bold),
            NoteInlineRun(text: " is ", style: .plain),
            NoteInlineRun(text: "spread", style: .italic),
            NoteInlineRun(text: " via ", style: .plain),
            NoteInlineRun(text: "Q3-Q1", style: .code),
            NoteInlineRun(text: " done", style: .plain),
        ])
    }

    func testUnclosedMarkersStayLiteral() {
        XCTAssertEqual(NoteMarkdown.runs("a ** b"), plain("a ** b"))
        XCTAssertEqual(NoteMarkdown.runs("2 * 3 = 6"), plain("2 * 3 = 6"))
    }

    func testFourPlusHashesStillParseAsDeepestHeading() {
        XCTAssertEqual(NoteMarkdown.blocks("#### Deep"), [.heading(level: 3, runs: plain("Deep"))])
    }

    func testBareAbsoluteValuePipesAreNotATable() {
        XCTAssertEqual(NoteMarkdown.blocks("|x - 5|"), [.paragraph(indent: 0, runs: plain("|x - 5|"))])
    }

    func testBulletIndentIsClamped() {
        let deep = String(repeating: " ", count: 40) + "- way in"
        guard case .bullet(let indent, _)? = NoteMarkdown.blocks(deep).first else {
            return XCTFail("expected a bullet")
        }
        XCTAssertLessThanOrEqual(indent, 6)
    }

    func testFlowRequiresArrow() {
        // A line that says "flow:" but has no steps is just a paragraph.
        XCTAssertEqual(NoteMarkdown.blocks("flow: nothing here"), [.paragraph(indent: 0, runs: plain("flow: nothing here"))])
    }
}
