import Foundation

/// Display-time math beautification for `code` spans: `sqrt` becomes √, simple exponents
/// become superscripts, `*` becomes ·, comparisons get real glyphs. Applied only when
/// rendering; the stored note text stays plain ASCII so it remains editable and parseable.
public enum MathPrettifier {
    public static func pretty(_ code: String) -> String {
        var text = code
        for (pattern, replacement) in Self.wordSwaps {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = superscripting(text)
        return text
    }

    /// Order matters: multi-character operators before single ones.
    private static let wordSwaps: [(String, String)] = [
        (#"\bsqrt\b"#, "√"),
        (#"\bpi\b"#, "π"),
        (#"\bsigma\b"#, "σ"),
        (#"\bmu\b"#, "μ"),
        (#"\binfinity\b"#, "∞"),
        (#"<="#, "≤"),
        (#">="#, "≥"),
        (#"!="#, "≠"),
        (#"\+/-"#, "±"),
        (#"\s\*\s"#, " · "),
        (#"\*"#, "·"),
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "-": "⁻", "+": "⁺", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "x": "ˣ",
    ]

    /// Converts `^token` to superscript when every character of the token maps; otherwise
    /// the caret stays and scanning continues inside the token (so `e^(-x^2/2)` keeps its
    /// outer group but still converts the inner `^2`).
    private static func superscripting(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let caret = rest.firstIndex(of: "^") {
            result += rest[..<caret]
            let after = rest[rest.index(after: caret)...]
            if let (token, remainder) = exponentToken(after), let converted = mapped(token) {
                result += converted
                rest = remainder
            } else {
                result.append("^")
                rest = after
            }
        }
        result += rest
        return result
    }

    /// The exponent right after a caret: a parenthesized group, or a signed number, or a
    /// single letter.
    private static func exponentToken(_ text: Substring) -> (Substring, Substring)? {
        guard let first = text.first else { return nil }
        if first == "(" {
            guard let close = text.firstIndex(of: ")") else { return nil }
            return (text[...close], text[text.index(after: close)...])
        }
        var end = text.startIndex
        if first == "-" || first == "+" { end = text.index(after: end) }
        var sawDigit = false
        while end < text.endIndex, text[end].isNumber {
            sawDigit = true
            end = text.index(after: end)
        }
        if !sawDigit {
            // No digits: allow exactly one letter (x^n, x^i).
            guard end < text.endIndex, text[end].isLetter else { return nil }
            end = text.index(after: end)
        }
        guard end > text.startIndex else { return nil }
        return (text[..<end], text[end...])
    }

    private static func mapped(_ token: Substring) -> String? {
        var converted = ""
        for char in token {
            guard let sup = superscripts[char] else { return nil }
            converted.append(sup)
        }
        return converted
    }
}
