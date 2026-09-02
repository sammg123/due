import Foundation

/// Hardens model output into a valid scene, mirroring what OllamaClient.sanitize does for
/// text: extract the JSON (models wrap it in prose and code fences), decode tolerantly,
/// drop elements that can't render, clamp everything onto the canvas.
public enum DrawingCodec {
    public static let maxElements = 120
    public static let maxStrokePoints = 600
    public static let defaultTextSize: Double = 16

    /// nil when no JSON object could be extracted at all; an empty array is a VALID scene
    /// ("delete everything" is a legitimate edit).
    public static func decodeScene(_ modelOutput: String) -> [DrawingElement]? {
        guard let start = modelOutput.firstIndex(of: "{"),
              let end = modelOutput.lastIndex(of: "}"),
              start < end
        else { return nil }
        // A single hallucinated literal like 1e999 makes JSONDecoder reject the WHOLE
        // document ("not representable in Swift") before per-element tolerance can run.
        // Cap giant positive exponents; the resulting huge-but-finite values get clamped.
        // Digit-before-e required so text content like "Route1999" is never touched.
        let text = String(modelOutput[start...end])
            .replacingOccurrences(of: #"([0-9.])[eE]\+?[0-9]{3,}"#, with: "$1e30", options: .regularExpression)
        let json = Data(text.utf8)
        // Drawing's own decoder already drops per-element failures.
        guard let scene = try? JSONDecoder().decode(SceneEnvelope.self, from: json) else { return nil }
        return Array(scene.unwrapped.compactMap(validated).prefix(maxElements))
    }

    /// Compact JSON the model reads when editing: no ids, no dates, only the fields the
    /// element's kind uses, so tokens aren't wasted and nothing confuses it.
    public static func encodeForModel(_ elements: [DrawingElement]) -> String {
        let dtos = elements.map(ModelElement.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Envelope(elements: dtos)) else { return #"{"elements":[]}"# }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Validation

    /// Rejects elements that can't render; clamps the rest onto the canvas.
    public static func validated(_ element: DrawingElement) -> DrawingElement? {
        var e = element
        switch e.kind {
        case .rect, .ellipse:
            guard e.w > 4, e.h > 4 else { return nil }
            e.w = min(e.w, Drawing.width)
            e.h = min(e.h, Drawing.height)
            e.x = e.x.clamped(0, Drawing.width - e.w)
            e.y = e.y.clamped(0, Drawing.height - e.h)
        case .arrow:
            e.from = clampPoint(e.from)
            e.to = clampPoint(e.to)
            guard e.from != e.to else { return nil }
        case .text:
            guard !e.text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            e.x = e.x.clamped(0, Drawing.width)
            e.y = e.y.clamped(0, Drawing.height)
            e.size = e.size <= 0 ? defaultTextSize : e.size.clamped(6, 120)
        case .stroke:
            guard e.points.count >= 2 else { return nil }
            e.points = e.points.prefix(maxStrokePoints).map(clampPoint)
            e.size = e.size <= 0 ? 3 : e.size.clamped(1, 40)
        case .plot:
            guard e.xMin < e.xMax, e.expression.count <= 300,
                  PlotFunction.parse(e.expression) != nil else { return nil }
        case .scatter:
            guard !e.points.isEmpty else { return nil }
            e.points = Array(e.points.prefix(maxStrokePoints))
        }
        return e
    }

    private static func clampPoint(_ p: DrawingPoint) -> DrawingPoint {
        DrawingPoint(x: p.x.clamped(0, Drawing.width), y: p.y.clamped(0, Drawing.height))
    }

    // MARK: - Wire types

    private struct SceneEnvelope: Decodable {
        let elements: [FailableElement]
        struct FailableElement: Decodable {
            let element: DrawingElement?
            init(from decoder: Decoder) { element = try? DrawingElement(from: decoder) }
        }
        var unwrapped: [DrawingElement] { elements.compactMap(\.element) }
    }

    private struct Envelope: Encodable {
        let elements: [ModelElement]
    }

    /// Only the fields this kind uses.
    private struct ModelElement: Encodable {
        let kind: String
        var points: [DrawingPoint]?
        var x, y, w, h: Double?
        var from, to: DrawingPoint?
        var text: String?
        var size: Double?
        var expression: String?
        var xMin, xMax: Double?
        var color: String?

        init(_ e: DrawingElement) {
            kind = e.kind.rawValue
            color = e.color.rawValue
            switch e.kind {
            case .stroke:
                points = e.points
                size = e.size
            case .rect, .ellipse:
                x = e.x; y = e.y; w = e.w; h = e.h
                if !e.text.isEmpty { text = e.text }
            case .arrow:
                from = e.from; to = e.to
                if !e.text.isEmpty { text = e.text }
            case .text:
                x = e.x; y = e.y
                text = e.text
                size = e.size
            case .plot:
                expression = e.expression
                xMin = e.xMin; xMax = e.xMax
            case .scatter:
                points = e.points
            }
        }
    }
}

private extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double {
        Swift.min(Swift.max(self, low), Swift.max(low, high))
    }
}
