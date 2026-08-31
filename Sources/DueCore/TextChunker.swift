import Foundation

/// Splits long text into model-sized chunks for the on-device polisher, which shares a
/// 4,096-token context window between prompt and response. Prefers paragraph boundaries,
/// then sentence boundaries, then a hard split.
public enum TextChunker {
    public static func chunks(_ text: String, limit: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""
        for paragraph in trimmed.components(separatedBy: "\n\n") {
            if paragraph.count > limit {
                flush(&current, into: &chunks)
                chunks.append(contentsOf: split(oversized: paragraph, limit: limit))
                continue
            }
            let joined = current.isEmpty ? paragraph : current + "\n\n" + paragraph
            if joined.count <= limit {
                current = joined
            } else {
                flush(&current, into: &chunks)
                current = paragraph
            }
        }
        flush(&current, into: &chunks)
        return chunks
    }

    private static func flush(_ current: inout String, into chunks: inout [String]) {
        guard !current.isEmpty else { return }
        chunks.append(current)
        current = ""
    }

    /// Packs sentences up to the limit; a single over-limit sentence is hard-split.
    private static func split(oversized paragraph: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(paragraph) {
            if sentence.count > limit {
                flush(&current, into: &chunks)
                chunks.append(contentsOf: hardSplit(sentence, limit: limit))
                continue
            }
            let joined = current.isEmpty ? sentence : current + " " + sentence
            if joined.count <= limit {
                current = joined
            } else {
                flush(&current, into: &chunks)
                current = sentence
            }
        }
        flush(&current, into: &chunks)
        return chunks
    }

    /// Splits after `.`, `!`, or `?` followed by whitespace. No trailing terminator = one sentence.
    private static func sentences(_ paragraph: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previousWasTerminator = false
        for char in paragraph {
            if previousWasTerminator, char.isWhitespace {
                let sentence = current.trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
                previousWasTerminator = false
                continue
            }
            current.append(char)
            previousWasTerminator = char == "." || char == "!" || char == "?"
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { result.append(last) }
        return result
    }

    private static func hardSplit(_ text: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            chunks.append(String(remaining.prefix(limit)))
            remaining = remaining.dropFirst(limit)
        }
        return chunks
    }
}
