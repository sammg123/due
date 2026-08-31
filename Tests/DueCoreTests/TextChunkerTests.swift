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
