import Foundation

public enum NoteInlineStyle: Equatable, Sendable {
    case plain, bold, italic, code
}

public struct NoteInlineRun: Equatable, Sendable {
    public let text: String
    public let style: NoteInlineStyle

    public init(text: String, style: NoteInlineStyle) {
        self.text = text
        self.style = style
    }
}

public enum NoteBlock: Equatable, Sendable {
    case heading(level: Int, runs: [NoteInlineRun])
    case bullet(indent: Int, runs: [NoteInlineRun])
    case numbered(number: Int, indent: Int, runs: [NoteInlineRun])
    case paragraph(indent: Int, runs: [NoteInlineRun])
    case callout(runs: [NoteInlineRun])
    case divider
    case table(header: [String], rows: [[String]])
    case flow(steps: [String])
    case drawing(id: UUID)
}

/// Parses the small markdown dialect Due's notes use (the same one the AI actions emit)
/// into renderable blocks. Forgiving by design: anything unrecognized is a paragraph, and
/// hand-typed indentation is preserved as paragraph indent so plain notes render well too.
public enum NoteMarkdown {
    public static func blocks(_ text: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var tableLines: [String] = []

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            blocks.append(parseTable(tableLines))
            tableLines = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // A table row needs an interior pipe (2+ cells); bare `|x - 5|` math stays text.
            if line.hasPrefix("|"), line.hasSuffix("|"), line.dropFirst().dropLast().contains("|") {
                tableLines.append(line)
                continue
            }
            flushTable()
            guard !line.isEmpty else { continue }

            if let heading = parseHeading(line) {
                blocks.append(heading)
            } else if let drawingID = parseDrawingMarker(line) {
                blocks.append(.drawing(id: drawingID))
            } else if isDivider(line) {
                blocks.append(.divider)
            } else if line.hasPrefix("> ") {
                blocks.append(.callout(runs: runs(String(line.dropFirst(2)))))
            } else if let flow = parseFlow(line) {
                blocks.append(flow)
            } else if let listItem = parseListItem(rawLine) {
                blocks.append(listItem)
            } else {
                blocks.append(.paragraph(indent: indentLevel(of: rawLine), runs: runs(line)))
            }
        }
        flushTable()
        return blocks
    }

    // MARK: - Line parsers

    private static func parseHeading(_ line: String) -> NoteBlock? {
        // Consume every leading '#' (so '####' still parses), then cap the render level at 3.
        var count = 0
        var rest = Substring(line)
        while rest.first == "#" {
            count += 1
            rest = rest.dropFirst()
        }
        guard count > 0, rest.first == " " else { return nil }
        return .heading(level: min(count, 3), runs: runs(rest.trimmingCharacters(in: .whitespaces)))
    }

    private static func isDivider(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == "-" }
    }

    /// `[drawing: <uuid>]` on its own line places an attached drawing.
    static func parseDrawingMarker(_ line: String) -> UUID? {
        let lowered = line.lowercased()
        guard lowered.hasPrefix("[drawing:"), line.hasSuffix("]") else { return nil }
        let inner = line.dropFirst("[drawing:".count).dropLast().trimmingCharacters(in: .whitespaces)
        return UUID(uuidString: inner)
    }

    private static func parseFlow(_ line: String) -> NoteBlock? {
        let lowered = line.lowercased()
        guard lowered.hasPrefix("flow:") else { return nil }
        let body = line.dropFirst("flow:".count)
        let steps = body.components(separatedBy: "->")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard steps.count >= 2 else { return nil }
        return .flow(steps: steps)
    }

    /// `- ` / `* ` bullets and `1. ` numbered items, nested two spaces per level.
    /// Clamped so pasted deep indentation can't push content off-screen.
    private static func parseListItem(_ rawLine: String) -> NoteBlock? {
        let indent = min(leadingSpaces(of: rawLine) / 2, 6)
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return .bullet(indent: indent, runs: runs(String(line.dropFirst(2))))
        }
        let head = line.prefix { $0.isNumber }
        if !head.isEmpty, line.dropFirst(head.count).hasPrefix(". "), let number = Int(head) {
            return .numbered(number: number, indent: indent, runs: runs(String(line.dropFirst(head.count + 2))))
        }
        return nil
    }

    private static func parseTable(_ lines: [String]) -> NoteBlock {
        var rows = lines.map { line in
            line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        // Drop the |---|---| separator row markdown puts under the header.
        rows.removeAll { row in
            row.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" } }
        }
        guard let header = rows.first else { return .table(header: [], rows: []) }
        return .table(header: header, rows: Array(rows.dropFirst()))
    }

    private static func leadingSpaces(of line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " { count += 1 } else if char == "\t" { count += 4 } else { break }
        }
        return count
    }

    /// Hand-typed notes indent with 4 spaces or a tab; render one visual level per 4.
    private static func indentLevel(of rawLine: String) -> Int {
        min(leadingSpaces(of: rawLine) / 4, 4)
    }

    // MARK: - Inline runs

    /// Splits inline text into styled runs: `**bold**`, `*italic*`, `` `code` ``.
    /// Unclosed markers stay literal text.
    public static func runs(_ text: String) -> [NoteInlineRun] {
        var result: [NoteInlineRun] = []
        var plain = ""
        var rest = Substring(text)

        func flushPlain() {
            guard !plain.isEmpty else { return }
            result.append(NoteInlineRun(text: plain, style: .plain))
            plain = ""
        }

        while let first = rest.first {
            if rest.hasPrefix("**"), let inner = delimited(rest, open: "**", close: "**") {
                flushPlain()
                result.append(NoteInlineRun(text: inner.content, style: .bold))
                rest = inner.remainder
            } else if first == "`", let inner = delimited(rest, open: "`", close: "`") {
                flushPlain()
                result.append(NoteInlineRun(text: inner.content, style: .code))
                rest = inner.remainder
            } else if first == "*", let inner = delimited(rest, open: "*", close: "*"), !inner.content.isEmpty,
                      inner.content.first != " ", inner.content.last != " " {
                // " * " with spaces around the content reads as multiplication, not emphasis.
                flushPlain()
                result.append(NoteInlineRun(text: inner.content, style: .italic))
                rest = inner.remainder
            } else {
                plain.append(first)
                rest = rest.dropFirst()
            }
        }
        flushPlain()
        return result.isEmpty ? [NoteInlineRun(text: "", style: .plain)] : result
    }

    private static func delimited(_ text: Substring, open: String, close: String) -> (content: String, remainder: Substring)? {
        let afterOpen = text.dropFirst(open.count)
        guard let closeRange = afterOpen.range(of: close), closeRange.lowerBound != afterOpen.startIndex else { return nil }
        return (String(afterOpen[..<closeRange.lowerBound]), afterOpen[closeRange.upperBound...])
    }
}
