import Foundation

/// Picks where to cut a live audio stream into transcription chunks. Cutting mid-word garbles
/// the words on both sides, so the cut lands in the most recent near-silent pause when one
/// exists in the search window; otherwise the chunk is taken whole.
public enum AudioChunk {
    /// RMS below this over a full window counts as a pause. Speech RMS runs ~0.005–0.15;
    /// lecture-hall ambience sits under ~0.01.
    static let silenceRMSThreshold: Float = 0.012
    /// A pause must be at least this long to cut in (seconds).
    static let windowSeconds = 0.3
    /// How far apart candidate windows start (seconds).
    static let stepSeconds = 0.1

    /// Returns the sample index to cut at: the end of the latest near-silent window inside the
    /// last `searchWindowSeconds`, or `samples.count` when there is no pause to use.
    public static func cutPoint(samples: [Float], sampleRate: Int, searchWindowSeconds: Int) -> Int {
        let window = Int(windowSeconds * Double(sampleRate))
        let step = Int(stepSeconds * Double(sampleRate))
        guard samples.count > window, window > 0, step > 0 else { return samples.count }

        let searchStart = max(0, samples.count - searchWindowSeconds * sampleRate)
        var windowEnd = samples.count
        while windowEnd - window >= searchStart {
            let start = windowEnd - window
            if rms(samples, from: start, count: window) < silenceRMSThreshold {
                return windowEnd
            }
            windowEnd -= step
        }
        return samples.count
    }

    private static func rms(_ samples: [Float], from start: Int, count: Int) -> Float {
        var sum: Float = 0
        for i in start..<(start + count) {
            sum += samples[i] * samples[i]
        }
        return (sum / Float(count)).squareRoot()
    }
}
