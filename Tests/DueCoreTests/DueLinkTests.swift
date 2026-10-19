import XCTest
@testable import DueCore

final class DueLinkTests: XCTestCase {
    func test_urls_useTheDueScheme() {
        XCTAssertEqual(DueLink.add.url.absoluteString, "due://add")
        XCTAssertEqual(DueLink.open.url.absoluteString, "due://open")
        XCTAssertEqual(DueLink.notes.url.absoluteString, "due://notes")
    }

    func test_everyLink_roundTripsThroughItsURL() {
        for link in DueLink.allCases {
            XCTAssertEqual(DueLink(url: link.url), link)
        }
    }

    func test_parsing_ignoresCaseAndATrailingSlash() {
        XCTAssertEqual(DueLink(url: URL(string: "DUE://ADD")!), .add)
        XCTAssertEqual(DueLink(url: URL(string: "due://open/")!), .open)
        XCTAssertEqual(DueLink(url: URL(string: "Due://Notes")!), .notes)
    }

    func test_parsing_rejectsOtherSchemesAndUnknownActions() {
        XCTAssertNil(DueLink(url: URL(string: "https://add")!))
        XCTAssertNil(DueLink(url: URL(string: "due://delete")!))
        XCTAssertNil(DueLink(url: URL(string: "due:")!))
    }
}
