import Foundation

/// Guards against AI fabrication. A model given a content-free chunk (a bare heading, say)
/// invents a plausible lecture to fill it, and nothing in the output alone reveals that.
/// Two checks: chunks without substance never go to a model at all, and rewritten chunks
/// must retain enough of the input's own vocabulary to plausibly derive from it.
public enum NoteGrounding {
    /// Minimum non-heading characters before a chunk is worth sending to a model.
    static let substanceFloor = 80
    /// Fraction of the input's distinctive words that must survive into the output.
    static let vocabularyFloor = 0.2
    static let minAnchors = 8
    static let maxAnchors = 60

    /// True when the chunk contains real content beyond headings, dividers, and markers.
    public static func hasSubstance(_ chunk: String) -> Bool {
        let content = chunk.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("[drawing:") && !$0.allSatisfy({ $0 == "-" }) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.count >= substanceFloor
    }

    /// True when `output` plausibly derives from `input`: enough of the input's distinctive
    /// words (6+ letters) appear in it. Inputs with too few such words always pass; the
    /// substance check is the guard for those.
    public static func sharesVocabulary(output: String, input: String) -> Bool {
        let anchors = anchorWords(input)
        guard anchors.count >= minAnchors else { return true }
        let haystack = output.lowercased()
        let hits = anchors.filter { haystack.contains($0) }.count
        return Double(hits) / Double(anchors.count) >= vocabularyFloor
    }

    /// The input's distinctive words: 6+ letters, lowercased, first-seen order, capped.
    static func anchorWords(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.lowercased().components(separatedBy: CharacterSet.letters.inverted) {
            guard raw.count >= 6, !seen.contains(raw) else { continue }
            seen.insert(raw)
            result.append(raw)
            if result.count >= maxAnchors { break }
        }
        return result
    }
}
