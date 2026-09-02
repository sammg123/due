import Foundation

/// A parsed y = f(x) expression for graph elements. Its own tiny recursive-descent parser,
/// never an eval: expressions come from the user and the model. Supports + - * / ^ (right
/// associative), parentheses, unary minus, implicit multiplication (2x), the variable x,
/// constants pi and e, and sin cos tan exp ln log sqrt abs.
public struct PlotFunction: Sendable {
    private let root: Node

    public static func parse(_ expression: String) -> PlotFunction? {
        var parser = Parser(tokens: tokenize(expression))
        guard let node = parser.parseExpression(), parser.isAtEnd else { return nil }
        return PlotFunction(root: node)
    }

    /// nil where the function is undefined (division by zero, sqrt of a negative, ...).
    public func evaluate(at x: Double) -> Double? {
        let value = root.evaluate(x: x)
        return value.isFinite ? value : nil
    }

    // MARK: - AST

    private indirect enum Node: Sendable {
        case number(Double)
        case variable
        case add(Node, Node), subtract(Node, Node), multiply(Node, Node), divide(Node, Node), power(Node, Node)
        case negate(Node)
        case function(String, Node)

        func evaluate(x: Double) -> Double {
            switch self {
            case .number(let v): return v
            case .variable: return x
            case .add(let a, let b): return a.evaluate(x: x) + b.evaluate(x: x)
            case .subtract(let a, let b): return a.evaluate(x: x) - b.evaluate(x: x)
            case .multiply(let a, let b): return a.evaluate(x: x) * b.evaluate(x: x)
            case .divide(let a, let b): return a.evaluate(x: x) / b.evaluate(x: x)
            case .power(let a, let b): return pow(a.evaluate(x: x), b.evaluate(x: x))
            case .negate(let a): return -a.evaluate(x: x)
            case .function(let name, let arg):
                let v = arg.evaluate(x: x)
                switch name {
                case "sin": return sin(v)
                case "cos": return cos(v)
                case "tan": return tan(v)
                case "exp": return exp(v)
                case "ln": return log(v)
                case "log": return log10(v)
                case "sqrt": return v.squareRoot()
                case "abs": return abs(v)
                default: return .nan
                }
            }
        }
    }

    private static let functionNames: Set<String> = ["sin", "cos", "tan", "exp", "ln", "log", "sqrt", "abs"]

    // MARK: - Tokenizer

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case op(Character)
        case open, close
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(text)
        while let first = rest.first {
            if first.isWhitespace {
                rest = rest.dropFirst()
            } else if first.isNumber || first == "." {
                let digits = rest.prefix { $0.isNumber || $0 == "." }
                guard let value = Double(digits) else { return [.op("?")] }
                tokens.append(.number(value))
                rest = rest.dropFirst(digits.count)
            } else if first.isLetter {
                let word = rest.prefix { $0.isLetter }
                tokens.append(.identifier(String(word).lowercased()))
                rest = rest.dropFirst(word.count)
            } else if "+-*/^".contains(first) {
                tokens.append(.op(first))
                rest = rest.dropFirst()
            } else if first == "(" {
                tokens.append(.open)
                rest = rest.dropFirst()
            } else if first == ")" {
                tokens.append(.close)
                rest = rest.dropFirst()
            } else {
                return [.op("?")] // unknown character poisons the whole parse
            }
        }
        return tokens
    }

    // MARK: - Parser

    private struct Parser {
        let tokens: [Token]
        var index = 0
        /// Recursion guard: parenthesis/function nesting recurses through the whole grammar,
        /// and a degenerate model output like "(((((...x...)))))" would otherwise blow the
        /// stack (measured: a few thousand parens crash a debug build). No real expression
        /// nests anywhere near this deep.
        var depth = 0
        static let maxDepth = 64

        var isAtEnd: Bool { index >= tokens.count }
        var current: Token? { isAtEnd ? nil : tokens[index] }

        mutating func parseExpression() -> Node? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else { return nil }
            guard var left = parseTerm() else { return nil }
            while case .op(let op) = current ?? .open, op == "+" || op == "-" {
                index += 1
                guard let right = parseTerm() else { return nil }
                left = op == "+" ? .add(left, right) : .subtract(left, right)
            }
            return left
        }

        mutating func parseTerm() -> Node? {
            guard var left = parseUnary() else { return nil }
            while true {
                if case .op(let op) = current ?? .open, op == "*" || op == "/" {
                    index += 1
                    guard let right = parseUnary() else { return nil }
                    left = op == "*" ? .multiply(left, right) : .divide(left, right)
                } else if isImplicitMultiplicand {
                    // "2x", "2sin(x)", "2(x+1)": adjacency multiplies.
                    guard let right = parseUnary() else { return nil }
                    left = .multiply(left, right)
                } else {
                    return left
                }
            }
        }

        /// True when the next token starts a new operand right after one ended.
        private var isImplicitMultiplicand: Bool {
            switch current {
            case .identifier, .open, .number: return true
            default: return false
            }
        }

        mutating func parseUnary() -> Node? {
            if case .op("-") = current ?? .open {
                index += 1
                guard let operand = parseUnary() else { return nil }
                return .negate(operand)
            }
            return parsePower()
        }

        mutating func parsePower() -> Node? {
            guard let base = parsePrimary() else { return nil }
            if case .op("^") = current ?? .open {
                index += 1
                // Right associative, and "-" after ^ binds to the exponent.
                guard let exponent = parseUnary() else { return nil }
                return .power(base, exponent)
            }
            return base
        }

        mutating func parsePrimary() -> Node? {
            switch current {
            case .number(let value):
                index += 1
                return .number(value)
            case .identifier(let name):
                index += 1
                switch name {
                case "x": return .variable
                case "pi": return .number(.pi)
                case "e": return .number(M_E)
                default:
                    guard PlotFunction.functionNames.contains(name), case .open = current ?? .close else { return nil }
                    index += 1
                    guard let arg = parseExpression(), case .close = current ?? .open else { return nil }
                    index += 1
                    return .function(name, arg)
                }
            case .open:
                index += 1
                guard let inner = parseExpression(), case .close = current ?? .open else { return nil }
                index += 1
                return inner
            default:
                return nil
            }
        }
    }
}
