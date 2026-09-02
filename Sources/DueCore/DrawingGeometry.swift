import Foundation

/// Pure geometry for the canvas editor: hit-testing, moving elements, and separating
/// overlapping AI-generated boxes (models are mediocre at spatial layout, so structure
/// comes from the model and exact geometry gets fixed up here).
public enum DrawingGeometry {
    public static let hitTolerance: Double = 14

    /// Topmost element under the point. Graph elements (plot/scatter) aren't selectable;
    /// they live in the shared axes layer.
    public static func hitTest(_ elements: [DrawingElement], at p: DrawingPoint, tolerance: Double = hitTolerance) -> UUID? {
        for element in elements.reversed() {
            switch element.kind {
            case .rect, .ellipse:
                if p.x >= element.x - tolerance, p.x <= element.x + element.w + tolerance,
                   p.y >= element.y - tolerance, p.y <= element.y + element.h + tolerance {
                    return element.id
                }
            case .arrow:
                if segmentDistance(p, element.from, element.to) <= tolerance { return element.id }
            case .stroke:
                for (a, b) in zip(element.points, element.points.dropFirst())
                where segmentDistance(p, a, b) <= tolerance {
                    return element.id
                }
            case .text:
                let w = Double(element.text.count) * element.size * 0.6 + tolerance
                let h = element.size * 1.4 + tolerance
                if p.x >= element.x - tolerance, p.x <= element.x + w,
                   p.y >= element.y - tolerance, p.y <= element.y + h {
                    return element.id
                }
            case .plot, .scatter:
                continue
            }
        }
        return nil
    }

    public static func moving(_ element: DrawingElement, dx: Double, dy: Double) -> DrawingElement {
        var e = element
        switch e.kind {
        case .rect, .ellipse, .text:
            e.x += dx
            e.y += dy
        case .arrow:
            e.from = DrawingPoint(x: e.from.x + dx, y: e.from.y + dy)
            e.to = DrawingPoint(x: e.to.x + dx, y: e.to.y + dy)
        case .stroke:
            e.points = e.points.map { DrawingPoint(x: $0.x + dx, y: $0.y + dy) }
        case .plot, .scatter:
            break
        }
        return e
    }

    /// Nudges overlapping boxes (rect/ellipse) apart, carrying arrow endpoints that were
    /// anchored on a box along with it, so AI layouts stay connected after separation.
    public static func resolveOverlaps(_ elements: [DrawingElement]) -> [DrawingElement] {
        var boxes = elements.enumerated().filter { $0.element.kind == .rect || $0.element.kind == .ellipse }
        guard boxes.count > 1 else { return elements }
        var deltas = [UUID: (dx: Double, dy: Double)]()

        // Record which box each arrow endpoint is anchored to BEFORE moving anything.
        struct Anchor { let arrowIndex: Int, isFrom: Bool, boxID: UUID }
        var anchors: [Anchor] = []
        for (i, e) in elements.enumerated() where e.kind == .arrow {
            for (isFrom, point) in [(true, e.from), (false, e.to)] {
                if let box = boxes.min(by: { boxDistance($0.element, point) < boxDistance($1.element, point) }),
                   boxDistance(box.element, point) < 40 {
                    anchors.append(Anchor(arrowIndex: i, isFrom: isFrom, boxID: box.element.id))
                }
            }
        }

        for _ in 0..<24 {
            var moved = false
            for i in 0..<boxes.count {
                for j in (i + 1)..<boxes.count {
                    let a = boxes[i].element, b = boxes[j].element
                    let overlapX = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
                    let overlapY = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
                    guard overlapX > 8, overlapY > 8 else { continue }
                    moved = true
                    // Push apart along the axis needing the smaller correction, half each.
                    if overlapX < overlapY {
                        let push = (overlapX / 2 + 8) * (a.x <= b.x ? 1.0 : -1.0)
                        shift(&boxes[i].element, dx: -push, dy: 0, deltas: &deltas)
                        shift(&boxes[j].element, dx: push, dy: 0, deltas: &deltas)
                    } else {
                        let push = (overlapY / 2 + 8) * (a.y <= b.y ? 1.0 : -1.0)
                        shift(&boxes[i].element, dx: 0, dy: -push, deltas: &deltas)
                        shift(&boxes[j].element, dx: 0, dy: push, deltas: &deltas)
                    }
                }
            }
            if !moved { break }
        }

        var result = elements
        for box in boxes {
            var e = box.element
            e.x = min(max(e.x, 0), Drawing.width - e.w)
            e.y = min(max(e.y, 0), Drawing.height - e.h)
            result[box.offset] = e
        }
        for anchor in anchors {
            guard let delta = deltas[anchor.boxID] else { continue }
            var arrow = result[anchor.arrowIndex]
            if anchor.isFrom {
                arrow.from = DrawingPoint(x: arrow.from.x + delta.dx, y: arrow.from.y + delta.dy)
            } else {
                arrow.to = DrawingPoint(x: arrow.to.x + delta.dx, y: arrow.to.y + delta.dy)
            }
            result[anchor.arrowIndex] = arrow
        }
        return result
    }

    // MARK: - Helpers

    private static func shift(_ e: inout DrawingElement, dx: Double, dy: Double, deltas: inout [UUID: (dx: Double, dy: Double)]) {
        e.x += dx
        e.y += dy
        let previous = deltas[e.id] ?? (0, 0)
        deltas[e.id] = (previous.dx + dx, previous.dy + dy)
    }

    /// Distance from a point to a box's boundary (0 when on or inside).
    private static func boxDistance(_ box: DrawingElement, _ p: DrawingPoint) -> Double {
        let dx = max(box.x - p.x, 0, p.x - (box.x + box.w))
        let dy = max(box.y - p.y, 0, p.y - (box.y + box.h))
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func segmentDistance(_ p: DrawingPoint, _ a: DrawingPoint, _ b: DrawingPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
        }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        let px = a.x + t * dx - p.x, py = a.y + t * dy - p.y
        return (px * px + py * py).squareRoot()
    }
}
