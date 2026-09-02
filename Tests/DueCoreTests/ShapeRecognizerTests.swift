import XCTest
@testable import DueCore

final class ShapeRecognizerTests: XCTestCase {
    private func jitter(_ v: Double, _ i: Int) -> Double {
        v + Double((i * 7) % 5) - 2 // deterministic wobble in -2...2
    }

    func testRecognizesRoughLine() {
        let points = (0...30).map { i in
            DrawingPoint(x: 100 + Double(i) * 10, y: jitter(200 + Double(i) * 3, i))
        }
        guard case .line(let from, let to)? = ShapeRecognizer.recognize(points) else {
            return XCTFail("expected a line")
        }
        XCTAssertEqual(from.x, 100, accuracy: 15)
        XCTAssertEqual(to.x, 400, accuracy: 15)
    }

    func testRecognizesRoughEllipse() {
        let points = (0...60).map { i -> DrawingPoint in
            let angle = Double(i) / 60 * 2 * .pi
            return DrawingPoint(x: jitter(500 + 150 * cos(angle), i), y: jitter(300 + 100 * sin(angle), i))
        }
        guard case .ellipse(let x, let y, let w, let h)? = ShapeRecognizer.recognize(points) else {
            return XCTFail("expected an ellipse")
        }
        XCTAssertEqual(x, 350, accuracy: 20)
        XCTAssertEqual(y, 200, accuracy: 20)
        XCTAssertEqual(w, 300, accuracy: 30)
        XCTAssertEqual(h, 200, accuracy: 30)
    }

    func testRecognizesRoughRect() {
        var points: [DrawingPoint] = []
        for i in 0...15 { points.append(DrawingPoint(x: jitter(100 + Double(i) * 20, i), y: jitter(100, i))) }
        for i in 0...15 { points.append(DrawingPoint(x: jitter(400, i), y: jitter(100 + Double(i) * 10, i))) }
        for i in 0...15 { points.append(DrawingPoint(x: jitter(400 - Double(i) * 20, i), y: jitter(250, i))) }
        for i in 0...15 { points.append(DrawingPoint(x: jitter(100, i), y: jitter(250 - Double(i) * 10, i))) }
        guard case .rect(let x, let y, let w, let h)? = ShapeRecognizer.recognize(points) else {
            return XCTFail("expected a rect")
        }
        XCTAssertEqual(x, 100, accuracy: 20)
        XCTAssertEqual(y, 100, accuracy: 20)
        XCTAssertEqual(w, 300, accuracy: 30)
        XCTAssertEqual(h, 150, accuracy: 30)
    }

    func testScribbleIsNotRecognized() {
        let points = (0...50).map { i -> DrawingPoint in
            DrawingPoint(x: 200 + Double((i * 137) % 240), y: 200 + Double((i * 89) % 180))
        }
        XCTAssertNil(ShapeRecognizer.recognize(points))
    }

    func testTooShortStrokeIsNotRecognized() {
        let points = [DrawingPoint(x: 0, y: 0), DrawingPoint(x: 5, y: 5)]
        XCTAssertNil(ShapeRecognizer.recognize(points))
    }
}
