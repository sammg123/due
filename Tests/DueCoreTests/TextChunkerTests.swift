import XCTest
@testable import DueCore

final class TextChunkerTests: XCTestCase {
    func testShortTextIsOneChunk() {
        XCTAssertEqual(TextChunker.chunks("hello world", limit: 100), ["hello world"])
    }

    func testEmptyTextIsNoChunks() {
        XCTAssertEqual(TextChunker.chunks("   \n ", limit: 100), [])
    }

    func testSplitsOnParagraphBoundaries() {
        let a = String(repeating: "a", count: 60)
        let b = String(repeating: "b", count: 60)
        let chunks = TextChunker.chunks("\(a)\n\n\(b)", limit: 100)
        XCTAssertEqual(chunks, [a, b])
    }

    func testKeepsParagraphsTogetherWhenTheyFit() {
        let chunks = TextChunker.chunks("one\n\ntwo\n\nthree", limit: 100)
        XCTAssertEqual(chunks, ["one\n\ntwo\n\nthree"])
    }

    func testOversizedParagraphSplitsOnSentences() {
        let sentence = "This is a sentence. "
        let paragraph = String(repeating: sentence, count: 20).trimmingCharacters(in: .whitespaces)
        let chunks = TextChunker.chunks(paragraph, limit: 100)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 100)
        }
        // Nothing lost: rejoined content matches original modulo separators.
        let rejoined = chunks.joined(separator: " ")
        XCTAssertEqual(rejoined.filter { !$0.isWhitespace }, paragraph.filter { !$0.isWhitespace })
    }

    func testHeadingBeforeOversizedParagraphRidesWithTheContent() {
        // The bug that fabricated a lecture: a transcript is one huge paragraph under a
        // heading, and the heading must never become a content-free chunk of its own.
        let paragraph = String(repeating: "Words in a real sentence here. ", count: 20)
        let chunks = TextChunker.chunks("## Lecture · Sep 2\n\n" + paragraph, limit: 200)
        XCTAssertTrue(chunks[0].hasPrefix("## Lecture · Sep 2"))
        XCTAssertGreaterThan(chunks[0].count, 60, "heading chunk carries real content")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 200)
        }
    }

    func testHardSplitWhenNoSentenceBoundaryExists() {
        let blob = String(repeating: "x", count: 250)
        let chunks = TextChunker.chunks(blob, limit: 100)
        XCTAssertEqual(chunks.count, 3)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 100)
        }
        XCTAssertEqual(chunks.joined(), blob)
    }
}
