import Foundation

/// Deterministic stroke beautification for assisted drawing: fits a rough freehand stroke
/// to a line, rectangle, or ellipse. No AI involved; instant and predictable, and undo
/// always restores the original ink.
public enum ShapeRecognizer {
    public enum Shape: Equatable, Sendable {
        case line(from: DrawingPoint, to: DrawingPoint)
        case rect(x: Double, y: Double, w: Double, h: Double)
        case ellipse(x: Double, y: Double, w: Double, h: Double)
    }

    public static func recognize(_ points: [DrawingPoint]) -> Shape? {
        guard points.count >= 8 else { return nil }
        let length = pathLength(points)
        guard length >= 60 else { return nil }
        guard let first = points.first, let last = points.last else { return nil }

        let closureDistance = distance(first, last)
        let isClosed = closureDistance < max(30, 0.25 * length)

        if !isClosed {
            return lineFit(points, length: length)
        }
        return closedShapeFit(points)
    }

    // MARK: - Line

    private static func lineFit(_ points: [DrawingPoint], length: Double) -> Shape? {
        guard let first = points.first, let last = points.last else { return nil }
        let chord = distance(first, last)
        // A straight-ish stroke travels nearly all of its path along the chord.
        guard chord > 0.85 * length else { return nil }
        let tolerance = max(10, 0.06 * chord)
        for p in points where perpendicularDistance(p, first, last) > tolerance {
            return nil
        }
        return .line(from: first, to: last)
    }

    // MARK: - Closed shapes

    private static func closedShapeFit(_ points: [DrawingPoint]) -> Shape? {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX, h = maxY - minY
        guard w > 25, h > 25 else { return nil }
        let cx = minX + w / 2, cy = minY + h / 2
        let a = w / 2, b = h / 2

        // Ellipse error: mean deviation of the normalized radius from 1.
        let ellipseError = points.reduce(0.0) { sum, p in
            let nx = (p.x - cx) / a, ny = (p.y - cy) / b
            return sum + abs((nx * nx + ny * ny).squareRoot() - 1)
        } / Double(points.count)

        // Rect error: mean distance to the nearest bounding-box edge, relative to size.
        let rectError = points.reduce(0.0) { sum, p in
            let dx = min(abs(p.x - minX), abs(p.x - maxX))
            let dy = min(abs(p.y - minY), abs(p.y - maxY))
            return sum + min(dx, dy)
        } / Double(points.count) / min(a, b)

        if ellipseError < 0.16, ellipseError * 1.2 < rectError * 2 {
            // An ellipse hugs its own outline much better than a rect hugs a circle.
            if ellipseError < rectError { return .ellipse(x: minX, y: minY, w: w, h: h) }
        }
        if rectError < 0.14 { return .rect(x: minX, y: minY, w: w, h: h) }
        if ellipseError < 0.16 { return .ellipse(x: minX, y: minY, w: w, h: h) }
        return nil
    }

    // MARK: - Geometry helpers

    private static func pathLength(_ points: [DrawingPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ a: DrawingPoint, _ b: DrawingPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private static func perpendicularDistance(_ p: DrawingPoint, _ a: DrawingPoint, _ b: DrawingPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        let clamped = min(max(t, 0), 1)
        let proj = DrawingPoint(x: a.x + clamped * dx, y: a.y + clamped * dy)
        return distance(p, proj)
    }
}
