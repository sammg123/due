import XCTest
@testable import DueCore

final class ArrayMoveTests: XCTestCase {
    private let letters = ["a", "b", "c", "d"]

    func test_moving_singleElementForward() {
        XCTAssertEqual(letters.moving(fromOffsets: [0], toOffset: 2), ["b", "a", "c", "d"])
    }

    func test_moving_singleElementToFront() {
        XCTAssertEqual(letters.moving(fromOffsets: [3], toOffset: 0), ["d", "a", "b", "c"])
    }

    func test_moving_multipleContiguousElementsToFront() {
        XCTAssertEqual(letters.moving(fromOffsets: [1, 2], toOffset: 0), ["b", "c", "a", "d"])
    }

    func test_moving_singleElementToEnd() {
        XCTAssertEqual(letters.moving(fromOffsets: [0], toOffset: 4), ["b", "c", "d", "a"])
    }

    func test_moving_emptyOffsets_isIdentity() {
        XCTAssertEqual(letters.moving(fromOffsets: [], toOffset: 2), letters)
    }
}
