import XCTest
@testable import DueCore

final class DrawingCodecTests: XCTestCase {
    func testDecodesFencedJSONWithPreamble() {
        let output = """
        Here is the scene:
        ```json
        {"elements":[{"kind":"rect","x":10,"y":10,"w":200,"h":80,"text":"start"}]}
        ```
        """
        let scene = DrawingCodec.decodeScene(output)
        XCTAssertEqual(scene?.count, 1)
        XCTAssertEqual(scene?.first?.text, "start")
    }

    func testClampsOutOfCanvasCoordinates() throws {
        let output = #"{"elements":[{"kind":"rect","x":-50,"y":9000,"w":5000,"h":100,"text":"big"}]}"#
        let element = try XCTUnwrap(DrawingCodec.decodeScene(output)?.first)
        XCTAssertGreaterThanOrEqual(element.x, 0)
        XCTAssertLessThanOrEqual(element.y + element.h, Drawing.height)
        XCTAssertLessThanOrEqual(element.x + element.w, Drawing.width)
    }

    func testDropsInvalidElements() {
        let output = """
        {"elements":[
          {"kind":"rect","x":10,"y":10,"w":0,"h":0,"text":"degenerate"},
          {"kind":"plot","expression":"import os","xMin":0,"xMax":1},
          {"kind":"plot","expression":"x^2","xMin":2,"xMax":-2},
          {"kind":"arrow","from":{"x":5,"y":5},"to":{"x":5,"y":5}},
          {"kind":"text","x":10,"y":10,"text":""},
          {"kind":"text","x":10,"y":10,"text":"kept"}
        ]}
        """
        let scene = DrawingCodec.decodeScene(output)
        XCTAssertEqual(scene?.count, 1)
        XCTAssertEqual(scene?.first?.text, "kept")
    }

    func testValidEmptySceneIsEmptyNotNil() {
        XCTAssertEqual(DrawingCodec.decodeScene(#"{"elements":[]}"#)?.count, 0)
        XCTAssertNil(DrawingCodec.decodeScene("no json here at all"))
    }

    func testCapsElementCount() {
        let many = (0..<300).map { #"{"kind":"text","x":10,"y":10,"text":"t\#($0)"}"# }.joined(separator: ",")
        let scene = DrawingCodec.decodeScene(#"{"elements":[\#(many)]}"#)
        XCTAssertEqual(scene?.count, DrawingCodec.maxElements)
    }

    func testEncodeForModelOmitsIdsAndIrrelevantFields() throws {
        let scene = [DrawingElement.rect(x: 10, y: 20, w: 100, h: 50, label: "a", color: .teal)]
        let json = DrawingCodec.encodeForModel(scene)
        XCTAssertFalse(json.contains("\"id\""))
        XCTAssertFalse(json.contains("expression"))
        XCTAssertTrue(json.contains("\"text\":\"a\""))
        // Round trip: what we show the model decodes back.
        XCTAssertEqual(DrawingCodec.decodeScene(json)?.count, 1)
    }

    func testHugeExponentLiteralDoesNotKillTheWholeScene() {
        let output = #"{"elements":[{"kind":"text","x":1e999,"y":10,"text":"survivor"},{"kind":"text","x":10,"y":10,"text":"fine"}]}"#
        let scene = DrawingCodec.decodeScene(output)
        XCTAssertEqual(scene?.count, 2, "one bad literal must not discard every element")
        XCTAssertLessThanOrEqual(scene?.first?.x ?? .infinity, Drawing.width)
    }

    func testSizeIsClampedUpward() throws {
        let output = #"{"elements":[{"kind":"text","x":1,"y":1,"text":"big","size":1000000},{"kind":"stroke","points":[{"x":0,"y":0},{"x":9,"y":9}],"size":9999}]}"#
        let scene = try XCTUnwrap(DrawingCodec.decodeScene(output))
        XCTAssertLessThanOrEqual(scene[0].size, 120)
        XCTAssertLessThanOrEqual(scene[1].size, 40)
    }

    func testDefaultTextSizeApplied() throws {
        let element = try XCTUnwrap(DrawingCodec.decodeScene(#"{"elements":[{"kind":"text","x":1,"y":1,"text":"hi"}]}"#)?.first)
        XCTAssertGreaterThan(element.size, 0)
    }
}
