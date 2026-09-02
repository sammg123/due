import XCTest
@testable import DueCore

final class DrawingTests: XCTestCase {
    func testElementDecodingFillsDefaultsAndGeneratesID() throws {
        let json = #"{"kind":"rect","x":10,"y":20,"w":100,"h":50,"text":"sort"}"#
        let element = try JSONDecoder().decode(DrawingElement.self, from: Data(json.utf8))
        XCTAssertEqual(element.kind, .rect)
        XCTAssertEqual(element.text, "sort")
        XCTAssertEqual(element.color, .blue)
        XCTAssertEqual(element.points, [])
    }

    func testDrawingRoundTrips() throws {
        let drawing = Drawing(elements: [
            .rect(x: 10, y: 10, w: 200, h: 80, label: "start", color: .teal),
            .arrow(from: DrawingPoint(x: 210, y: 50), to: DrawingPoint(x: 400, y: 50), label: nil, color: .gray),
        ])
        let data = try JSONEncoder().encode(drawing)
        let decoded = try JSONDecoder().decode(Drawing.self, from: data)
        XCTAssertEqual(decoded.elements.count, 2)
        XCTAssertEqual(decoded.elements[0].text, "start")
        XCTAssertEqual(decoded.id, drawing.id)
    }

    func testUnknownKindFailsElementDecodeOnly() throws {
        let json = #"{"elements":[{"kind":"hologram","x":1},{"kind":"text","x":5,"y":5,"text":"hi"}]}"#
        let drawing = try JSONDecoder().decode(Drawing.self, from: Data(json.utf8))
        XCTAssertEqual(drawing.elements.count, 1)
        XCTAssertEqual(drawing.elements[0].kind, .text)
    }

    func testUpdatingElementsIsImmutable() {
        let drawing = Drawing(elements: [])
        let later = Date(timeIntervalSince1970: 2_000)
        let updated = drawing.updating(elements: [.text(x: 5, y: 5, string: "hi", size: 16, color: .gray)], at: later)
        XCTAssertEqual(updated.elements.count, 1)
        XCTAssertEqual(updated.updatedAt, later)
        XCTAssertTrue(drawing.elements.isEmpty)
    }
}
