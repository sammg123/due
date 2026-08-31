import XCTest
@testable import DueCore

final class AudioChunkTests: XCTestCase {
    private let rate = 16_000

    /// Loud everywhere except a quiet gap: the cut should land inside the gap.
    func testCutPointLandsInQuietGap() {
        var samples = [Float](repeating: 0.5, count: 10 * rate)
        let gapStart = 8 * rate
        let gapEnd = gapStart + rate / 2 // 500 ms of near-silence
        for i in gapStart..<gapEnd { samples[i] = 0.001 }
        let cut = AudioChunk.cutPoint(samples: samples, sampleRate: rate, searchWindowSeconds: 5)
        XCTAssertGreaterThanOrEqual(cut, gapStart)
        XCTAssertLessThanOrEqual(cut, gapEnd)
    }

    func testCutPointFallsBackToEndWhenNoQuietZone() {
        let samples = [Float](repeating: 0.5, count: 10 * rate)
        let cut = AudioChunk.cutPoint(samples: samples, sampleRate: rate, searchWindowSeconds: 5)
        XCTAssertEqual(cut, samples.count)
    }

    func testCutPointOnShortBufferIsEnd() {
        let samples = [Float](repeating: 0.1, count: rate / 2)
        XCTAssertEqual(AudioChunk.cutPoint(samples: samples, sampleRate: rate, searchWindowSeconds: 5), samples.count)
    }

    func testCutPointPrefersLatestQuietZone() {
        var samples = [Float](repeating: 0.5, count: 10 * rate)
        // Two quiet gaps in the search window; the later one should win (keeps chunks maximal).
        for i in (6 * rate)..<(6 * rate + rate / 2) { samples[i] = 0.001 }
        let lateStart = 9 * rate
        for i in lateStart..<(lateStart + rate / 2) { samples[i] = 0.001 }
        let cut = AudioChunk.cutPoint(samples: samples, sampleRate: rate, searchWindowSeconds: 5)
        XCTAssertGreaterThanOrEqual(cut, lateStart)
    }
}
