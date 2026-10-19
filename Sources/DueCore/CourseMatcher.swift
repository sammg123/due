import Foundation

/// Finds class mentions in quick-add text by rule, against the courses the user already has.
/// No model involved: "351", "econ", "economics", "eco", "ecom" all mean ECON351 when ECON351 is
/// the only course they fit. A word that fits two courses ("buad" with BUAD112 and BUAD312)
/// matches nothing, and the caller is told it was ambiguous.
public enum CourseMatcher {
    public enum Resolution: Equatable, Sendable {
        case course(String)
        case ambiguous([String])
        case none
    }

    public struct Extraction: Equatable, Sendable {
        /// The class the text names, if exactly one.
        public let course: String?
        /// The text with that class's mentions (and a connector like "in" or "for") removed.
        public let text: String
        /// True when a mention fit more than one class and nothing else settled it.
        public let isAmbiguous: Bool
    }

    /// What one token means against `known`. Stronger rules win: full name, then number, then
    /// subject word, then loose forms (prefix, suffix, one-key typo).
    public static func resolve(_ token: String, known: [String]) -> Resolution {
        rank(token, known: known.compactMap(CourseKey.init))?.resolution ?? .none
    }

    /// Finds the one class `text` names and removes its mentions. The text comes back with words
    /// separated by single spaces. If removing the mentions would leave nothing but filler, the
    /// words stay (so "econ" alone keeps its title) while the class is still returned.
    public static func extract(from text: String, known: [String]) -> Extraction {
        let tokens = words(in: text)
        let mentions = findMentions(in: tokens, known: known.compactMap(CourseKey.init))
        let chosen = mentions
            .filter { $0.candidates.count == 1 }
            .min { $0.tier < $1.tier }?
            .candidates.first
        guard let chosen else {
            return Extraction(course: nil, text: tokens.joined(separator: " "), isAmbiguous: mentions.contains { $0.candidates.count > 1 })
        }
        return Extraction(course: chosen, text: removing(chosen, mentions: mentions, from: tokens), isAmbiguous: false)
    }

    /// Removes mentions of `course` from `text` (used on titles the on-device model wrote).
    public static func strip(_ course: String, from text: String, known: [String]) -> String {
        let tokens = words(in: text)
        let mentions = findMentions(in: tokens, known: known.compactMap(CourseKey.init))
        return removing(course, mentions: mentions, from: tokens)
    }

    // MARK: - Rules

    private enum Tier: Int, Comparable {
        case fullName, number, subject, loose
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// A known course split into its parts: "ECON 351" -> key "econ351", subject "econ", number "351".
    private struct CourseKey {
        let name: String
        let key: String
        let subject: String
        let number: String?

        init?(_ name: String) {
            let key = String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
            guard !key.isEmpty else { return nil }
            let subject = String(key.prefix { $0.isLetter })
            let digits = String(key.dropFirst(subject.count).prefix { $0.isNumber })
            self.name = name
            self.key = key
            self.subject = subject
            self.number = digits.isEmpty ? nil : digits
        }
    }

    private struct Ranked {
        let tier: Tier
        let names: [String]
        var resolution: Resolution { names.count == 1 ? .course(names[0]) : .ambiguous(names) }
    }

    /// Course numbers shorter than this are never matched ("hw 6", "lab 11", "chapter 7").
    private static let minimumNumberLength = 3
    /// Course mentions shorter than this never match loosely.
    private static let minimumLooseLength = 3
    /// Typos are only forgiven on subjects at least this long.
    private static let minimumTypoLength = 4

    /// Endings that turn a subject into the word people type for the class: econ -> economics,
    /// writ -> writing, hist -> history. Plain "write" or "written" stay ordinary words.
    private static let subjectSuffixes: Set<String> = [
        "s", "es", "ing", "ic", "ics", "ical", "omic", "omics", "omy", "ology", "logy", "ory", "istry", "ish",
    ]

    /// Everyday words that must never count as a loose class mention, whatever the courses are.
    private static let commonWords: Set<String> = [
        "the", "and", "for", "his", "her", "him", "can", "are", "was", "not", "you", "all", "any",
        "one", "our", "out", "day", "get", "has", "how", "new", "now", "old", "see", "two", "way",
        "who", "did", "its", "let", "put", "say", "she", "too", "use", "due", "per", "pre", "pro",
        "sub", "act", "add", "ask", "bad", "big", "bit", "box", "buy", "car", "cut", "end", "far",
        "few", "fit", "fun", "got", "hot", "job", "key", "law", "lot", "low", "man", "may", "off",
        "own", "pay", "red", "run", "set", "top", "try", "win", "yes", "yet", "bus", "lab", "quiz",
        "test", "exam", "read", "work", "with", "that", "this", "what", "when", "from", "have",
        "will", "your", "wait", "icon",
    ]

    private static func rank(_ token: String, known: [CourseKey]) -> Ranked? {
        guard let t = normalized(token) else { return nil }
        var best: Ranked?
        for course in known {
            guard let tier = tier(of: t, for: course) else { continue }
            switch best {
            case .some(let current) where tier > current.tier:
                continue
            case .some(let current) where tier == current.tier:
                if !current.names.contains(course.name) { best = Ranked(tier: tier, names: current.names + [course.name]) }
            default:
                best = Ranked(tier: tier, names: [course.name])
            }
        }
        return best
    }

    private static func tier(of t: String, for course: CourseKey) -> Tier? {
        if t == course.key { return .fullName }
        if t.allSatisfy(\.isNumber) {
            return t.count >= minimumNumberLength && t == course.number ? .number : nil
        }
        guard t.allSatisfy(\.isLetter) else { return nil }
        guard course.number != nil else {
            // Letter-only courses (CLUBS, SAMMY): the whole word, singular or plural.
            return t + "s" == course.key || t == course.key + "s" ? .subject : nil
        }
        if course.subject.count >= 2, t == course.subject { return .subject }
        return isLooseMention(t, of: course.subject) ? .loose : nil
    }

    private static func isLooseMention(_ t: String, of subject: String) -> Bool {
        guard !commonWords.contains(t), t.count >= minimumLooseLength, subject.count >= minimumLooseLength else { return false }
        if t.hasPrefix(subject), subjectSuffixes.contains(String(t.dropFirst(subject.count))) { return true }
        if t.count < subject.count, subject.hasPrefix(t) { return true }
        return subject.count >= minimumTypoLength && isOneKeyTypo(t, of: subject)
    }

    /// One letter swapped for a neighboring key ("ecom" for "econ"), or two adjacent letters
    /// swapped ("wirt" for "writ"). Real words one letter away ("icon", "wait") are not neighbors.
    private static func isOneKeyTypo(_ a: String, of b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard x.count == y.count else { return false }
        let diffs = x.indices.filter { x[$0] != y[$0] }
        if diffs.count == 1 { return areNeighborKeys(x[diffs[0]], y[diffs[0]]) }
        if diffs.count == 2, diffs[1] == diffs[0] + 1 {
            return x[diffs[0]] == y[diffs[1]] && x[diffs[1]] == y[diffs[0]]
        }
        return false
    }

    private static let keyboardRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    /// How far each row sits to the right of the one above, in key widths.
    private static let rowOffsets: [Double] = [0, 0.25, 0.75]

    private static func areNeighborKeys(_ a: Character, _ b: Character) -> Bool {
        guard let pa = keyPosition(a), let pb = keyPosition(b), a != b else { return false }
        let dx = abs(pa.x - pb.x), dy = abs(pa.row - pb.row)
        return (dy == 0 && dx == 1) || (dy == 1 && dx < 1)
    }

    private static func keyPosition(_ c: Character) -> (row: Int, x: Double)? {
        for (row, keys) in keyboardRows.enumerated() {
            if let i = keys.firstIndex(of: c) {
                return (row, Double(keys.distance(from: keys.startIndex, to: i)) + rowOffsets[row])
            }
        }
        return nil
    }

    /// Lowercased letters and digits only, one leading "#" allowed. Anything with other
    /// characters ("10/12", "write-up", "econ's") is not a class mention.
    private static func normalized(_ token: String) -> String? {
        let body = token.hasPrefix("#") ? String(token.dropFirst()) : token
        let lower = body.lowercased()
        guard !lower.isEmpty, lower.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return lower
    }

    // MARK: - Mentions in text

    private struct Mention {
        let range: ClosedRange<Int>
        let tier: Tier
        let candidates: [String]
    }

    /// Words a number after which is a count, not a class: "page 351", "hw 312".
    private static let countWords: Set<String> = [
        "page", "pages", "pg", "pgs", "pp", "p", "chapter", "chapters", "ch", "chap", "section", "sec",
        "problem", "problems", "prob", "question", "questions", "q", "exercise", "exercises", "ex",
        "lab", "hw", "homework", "quiz", "unit", "module", "lecture", "lec", "week", "wk", "room",
        "rm", "no", "number", "num", "part", "step", "slide", "slides", "figure", "fig", "table", "pset",
    ]

    /// Words after which a number is an amount, not a class: "150 words", "312 points".
    private static let quantityWords: Set<String> = [
        "word", "words", "page", "pages", "point", "points", "pts", "min", "mins", "minutes",
        "question", "questions", "problems", "slides", "percent", "dollars",
    ]

    private static func findMentions(in tokens: [String], known: [CourseKey]) -> [Mention] {
        guard !known.isEmpty else { return [] }
        var mentions: [Mention] = []
        var i = 0
        while i < tokens.count {
            if let pair = splitName(at: i, in: tokens, known: known) {
                mentions.append(Mention(range: i...(i + 1), tier: .fullName, candidates: [pair]))
                i += 2
                continue
            }
            if let ranked = rank(tokens[i], known: known),
               !(ranked.tier == .number && isCountOrAmount(at: i, in: tokens)) {
                mentions.append(Mention(range: i...i, tier: ranked.tier, candidates: ranked.names))
            }
            i += 1
        }
        return mentions
    }

    private static func isCountOrAmount(at i: Int, in tokens: [String]) -> Bool {
        let before = i > 0 ? tokens[i - 1].lowercased() : ""
        let after = i + 1 < tokens.count ? tokens[i + 1].lowercased() : ""
        return countWords.contains(before) || quantityWords.contains(after)
    }

    /// "BUAD 312" typed as two words.
    private static func splitName(at i: Int, in tokens: [String], known: [CourseKey]) -> String? {
        guard i + 1 < tokens.count,
              let a = normalized(tokens[i]), a.allSatisfy(\.isLetter),
              let b = normalized(tokens[i + 1]), b.allSatisfy(\.isNumber) else { return nil }
        return known.first { $0.key == a + b }?.name
    }

    /// Words that only made sense next to the class: "homework IN econ", "econ CLASS".
    private static let connectorsBefore: Set<String> = ["in", "for", "of", "from"]
    /// "turn in econ essay" keeps its "in": the verb needs it.
    private static let phrasalVerbs: Set<String> = ["turn", "hand", "send", "fill", "check", "sign", "log", "put", "drop", "plug"]
    private static let wordsAfter: Set<String> = ["class", "classes", "course"]
    /// What a title can be left with that still counts as empty.
    private static let filler: Set<String> = ["due", "by", "on", "at", "@", "-", "in", "for", "of", "from", "the", "a"]

    private static func removing(_ course: String, mentions: [Mention], from tokens: [String]) -> String {
        var drop = Set<Int>()
        for m in mentions where m.candidates.contains(course) {
            drop.formUnion(m.range)
            let before = m.range.lowerBound - 1
            if before >= 0, isDroppableConnector(at: before, in: tokens) { drop.insert(before) }
            let after = m.range.upperBound + 1
            if after < tokens.count, wordsAfter.contains(tokens[after].lowercased()) { drop.insert(after) }
        }
        let kept = tokens.indices.filter { !drop.contains($0) }.map { tokens[$0] }
        let isOnlyFiller = kept.allSatisfy { filler.contains($0.lowercased()) }
        return (isOnlyFiller ? tokens : kept).joined(separator: " ")
    }

    private static func isDroppableConnector(at i: Int, in tokens: [String]) -> Bool {
        let word = tokens[i].lowercased()
        guard connectorsBefore.contains(word) else { return false }
        let isPhrasal = word == "in" && i > 0 && phrasalVerbs.contains(tokens[i - 1].lowercased())
        return !isPhrasal
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
