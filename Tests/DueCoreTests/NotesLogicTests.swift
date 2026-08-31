import XCTest
@testable import DueCore

final class NotesLogicTests: XCTestCase {
    private func note(_ title: String, course: String? = nil, updated: TimeInterval, body: String = "") -> Note {
        Note(title: title, course: course, body: body,
             createdAt: Date(timeIntervalSince1970: updated), updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testSortByDateEditedNewestFirst() {
        let a = note("A", updated: 100)
        let b = note("B", updated: 300)
        let c = note("C", updated: 200)
        let sorted = NotesLogic.sort([a, b, c], by: .dateEdited)
        XCTAssertEqual(sorted.map(\.title), ["B", "C", "A"])
    }

    func testSortByNameCaseInsensitiveUntitledLast() {
        let a = note("banana", updated: 1)
        let b = note("Apple", updated: 2)
        let untitled = note("", updated: 3)
        let sorted = NotesLogic.sort([a, untitled, b], by: .name)
        XCTAssertEqual(sorted.map(\.displayTitle), ["Apple", "banana", "Untitled"])
    }

    func testSortByCourseGroupsAlphabeticalNoCourseLastThenDate() {
        let m1 = note("m-old", course: "Math", updated: 100)
        let m2 = note("m-new", course: "Math", updated: 200)
        let bio = note("b", course: "Bio", updated: 50)
        let none = note("n", updated: 999)
        let sorted = NotesLogic.sort([m1, none, m2, bio], by: .course)
        XCTAssertEqual(sorted.map(\.title), ["b", "m-new", "m-old", "n"])
    }

    func testFilterByCourse() {
        let items = [note("a", course: "Math", updated: 1), note("b", course: "Bio", updated: 2), note("c", updated: 3)]
        XCTAssertEqual(NotesLogic.filter(items, course: "Math", search: "").map(\.title), ["a"])
        XCTAssertEqual(NotesLogic.filter(items, course: nil, search: "").count, 3)
    }

    func testSearchMatchesTitleBodyAndCourseCaseInsensitive() {
        let items = [
            note("Thermo lecture", updated: 1),
            note("x", updated: 2, body: "entropy is disorder"),
            note("y", course: "CHEM101", updated: 3),
        ]
        XCTAssertEqual(NotesLogic.filter(items, course: nil, search: "THERMO").map(\.title), ["Thermo lecture"])
        XCTAssertEqual(NotesLogic.filter(items, course: nil, search: "Entropy").map(\.title), ["x"])
        XCTAssertEqual(NotesLogic.filter(items, course: nil, search: "chem").map(\.title), ["y"])
        XCTAssertEqual(NotesLogic.filter(items, course: nil, search: "  ").count, 3)
    }

    func testGroupedByCourseKeepsSortOrderWithinGroups() {
        let items = [
            note("m-new", course: "Math", updated: 200),
            note("m-old", course: "Math", updated: 100),
            note("loose", updated: 300),
        ]
        let groups = NotesLogic.groupedByCourse(items)
        XCTAssertEqual(groups.map(\.course), ["Math", nil])
        XCTAssertEqual(groups[0].notes.map(\.title), ["m-new", "m-old"])
        XCTAssertEqual(groups[1].notes.map(\.title), ["loose"])
    }
}
