import Foundation

public struct DrawingPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One element of a drawing scene. Deliberately a single flat struct rather than an enum
/// with associated values: the AI emits these as uniform JSON objects, and tolerant
/// decoding (missing fields become defaults) keeps model output usable.
public struct DrawingElement: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case stroke   // freehand: `points`, `size` = line width
        case rect     // x/y/w/h frame, `text` = centered label
        case ellipse  // x/y/w/h frame, `text` = centered label
        case arrow    // from -> to, `text` = midpoint label
        case text     // x/y anchor, `text` content, `size` = font size
        case plot     // y = f(x): `expression` over xMin...xMax, shared graph axes
        case scatter  // data points in graph space, shared graph axes
    }

    public let id: UUID
    public var kind: Kind
    public var points: [DrawingPoint]
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var from: DrawingPoint
    public var to: DrawingPoint
    public var text: String
    public var size: Double
    public var expression: String
    public var xMin: Double
    public var xMax: Double
    public var color: PaletteColor

    public init(
        id: UUID = UUID(),
        kind: Kind,
        points: [DrawingPoint] = [],
        x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0,
        from: DrawingPoint = DrawingPoint(x: 0, y: 0),
        to: DrawingPoint = DrawingPoint(x: 0, y: 0),
        text: String = "",
        size: Double = 0,
        expression: String = "",
        xMin: Double = 0, xMax: Double = 0,
        color: PaletteColor = .blue
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.from = from
        self.to = to
        self.text = text
        self.size = size
        self.expression = expression
        self.xMin = xMin
        self.xMax = xMax
        self.color = color
    }

    /// Tolerant decoding: only `kind` is required; the model omits whatever doesn't apply.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        points = try c.decodeIfPresent([DrawingPoint].self, forKey: .points) ?? []
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        w = try c.decodeIfPresent(Double.self, forKey: .w) ?? 0
        h = try c.decodeIfPresent(Double.self, forKey: .h) ?? 0
        from = try c.decodeIfPresent(DrawingPoint.self, forKey: .from) ?? DrawingPoint(x: 0, y: 0)
        to = try c.decodeIfPresent(DrawingPoint.self, forKey: .to) ?? DrawingPoint(x: 0, y: 0)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0
        expression = try c.decodeIfPresent(String.self, forKey: .expression) ?? ""
        xMin = try c.decodeIfPresent(Double.self, forKey: .xMin) ?? 0
        xMax = try c.decodeIfPresent(Double.self, forKey: .xMax) ?? 0
        color = try c.decodeIfPresent(PaletteColor.self, forKey: .color) ?? .blue
    }

    // MARK: - Factories

    public static func stroke(points: [DrawingPoint], color: PaletteColor = .gray, width: Double = 3) -> DrawingElement {
        DrawingElement(kind: .stroke, points: points, size: width, color: color)
    }

    public static func rect(x: Double, y: Double, w: Double, h: Double, label: String?, color: PaletteColor = .blue) -> DrawingElement {
        DrawingElement(kind: .rect, x: x, y: y, w: w, h: h, text: label ?? "", color: color)
    }

    public static func ellipse(x: Double, y: Double, w: Double, h: Double, label: String?, color: PaletteColor = .blue) -> DrawingElement {
        DrawingElement(kind: .ellipse, x: x, y: y, w: w, h: h, text: label ?? "", color: color)
    }

    public static func arrow(from: DrawingPoint, to: DrawingPoint, label: String?, color: PaletteColor = .gray) -> DrawingElement {
        DrawingElement(kind: .arrow, from: from, to: to, text: label ?? "", color: color)
    }

    public static func text(x: Double, y: Double, string: String, size: Double = 16, color: PaletteColor = .gray) -> DrawingElement {
        DrawingElement(kind: .text, x: x, y: y, text: string, size: size, color: color)
    }

    public static func plot(expression: String, xMin: Double, xMax: Double, color: PaletteColor = .blue) -> DrawingElement {
        DrawingElement(kind: .plot, expression: expression, xMin: xMin, xMax: xMax, color: color)
    }
}

/// A vector scene attached to a note: stored as its own JSON file beside the notes
/// (like recordings), referenced from the body by a `[drawing: <id>]` line, rendered
/// natively, and readable/writable by the AI as structured JSON.
public struct Drawing: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var elements: [DrawingElement]
    public var createdAt: Date
    public var updatedAt: Date

    /// Normalized canvas space (x right, y down). Everything scales from this.
    public static let width: Double = 1000
    public static let height: Double = 750

    public init(id: UUID = UUID(), elements: [DrawingElement] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.elements = elements
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { elements.isEmpty }

    public func updating(elements: [DrawingElement], at date: Date = Date()) -> Drawing {
        var copy = self
        copy.elements = elements
        copy.updatedAt = date
        return copy
    }

    /// Tolerant decoding: an element that fails to decode (unknown kind from a newer
    /// version, malformed model output) is dropped, the rest survive.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let failable = try c.decodeIfPresent([FailableElement].self, forKey: .elements) ?? []
        elements = failable.compactMap(\.element)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    private struct FailableElement: Decodable {
        let element: DrawingElement?
        init(from decoder: Decoder) {
            element = try? DrawingElement(from: decoder)
        }
    }
}
