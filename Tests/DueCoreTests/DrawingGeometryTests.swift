import XCTest
@testable import DueCore

final class DrawingGeometryTests: XCTestCase {
    func testHitTestPicksTopmostAndRespectsKinds() {
        let bottom = DrawingElement.rect(x: 100, y: 100, w: 200, h: 100, label: "bottom")
        let top = DrawingElement.rect(x: 150, y: 120, w: 200, h: 100, label: "top")
        let plot = DrawingElement.plot(expression: "x", xMin: 0, xMax: 1)
        let elements = [bottom, top, plot]
        XCTAssertEqual(DrawingGeometry.hitTest(elements, at: DrawingPoint(x: 200, y: 150)), top.id)
        XCTAssertEqual(DrawingGeometry.hitTest(elements, at: DrawingPoint(x: 110, y: 105)), bottom.id)
        XCTAssertNil(DrawingGeometry.hitTest([plot], at: DrawingPoint(x: 500, y: 375)), "plots are not selectable")
    }

    func testHitTestArrowByDistance() {
        let arrow = DrawingElement.arrow(from: DrawingPoint(x: 0, y: 0), to: DrawingPoint(x: 100, y: 0), label: nil)
        XCTAssertEqual(DrawingGeometry.hitTest([arrow], at: DrawingPoint(x: 50, y: 10)), arrow.id)
        XCTAssertNil(DrawingGeometry.hitTest([arrow], at: DrawingPoint(x: 50, y: 40)))
    }

    func testMovingShiftsEveryKindCoherently() {
        let rect = DrawingGeometry.moving(.rect(x: 10, y: 10, w: 50, h: 50, label: nil), dx: 5, dy: -5)
        XCTAssertEqual(rect.x, 15)
        XCTAssertEqual(rect.y, 5)
        let stroke = DrawingGeometry.moving(.stroke(points: [DrawingPoint(x: 0, y: 0)]), dx: 3, dy: 4)
        XCTAssertEqual(stroke.points, [DrawingPoint(x: 3, y: 4)])
        let arrow = DrawingGeometry.moving(.arrow(from: DrawingPoint(x: 0, y: 0), to: DrawingPoint(x: 10, y: 0), label: nil), dx: 1, dy: 1)
        XCTAssertEqual(arrow.from, DrawingPoint(x: 1, y: 1))
    }

    func testResolveOverlapsSeparatesBoxesAndCarriesArrows() {
        let a = DrawingElement.rect(x: 100, y: 100, w: 200, h: 100, label: "a")
        let b = DrawingElement.rect(x: 150, y: 110, w: 200, h: 100, label: "b")
        let arrow = DrawingElement.arrow(from: DrawingPoint(x: 300, y: 150), to: DrawingPoint(x: 155, y: 160), label: nil)
        let resolved = DrawingGeometry.resolveOverlaps([a, b, arrow])
        let ra = resolved[0], rb = resolved[1]
        let overlapX = min(ra.x + ra.w, rb.x + rb.w) - max(ra.x, rb.x)
        let overlapY = min(ra.y + ra.h, rb.y + rb.h) - max(ra.y, rb.y)
        XCTAssertTrue(overlapX <= 8 || overlapY <= 8, "boxes no longer substantially overlap")
        // The arrow's `to` endpoint was anchored on box b and should have moved with it.
        XCTAssertNotEqual(resolved[2].to, arrow.to)
    }

    func testResolveOverlapsLeavesSeparatedScenesAlone() {
        let a = DrawingElement.rect(x: 0, y: 0, w: 100, h: 50, label: "a")
        let b = DrawingElement.rect(x: 400, y: 400, w: 100, h: 50, label: "b")
        XCTAssertEqual(DrawingGeometry.resolveOverlaps([a, b]), [a, b])
    }
}
