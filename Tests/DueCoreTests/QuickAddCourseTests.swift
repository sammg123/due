import XCTest
@testable import DueCore

/// `QuickAddParser.parse` with the user's known courses: class mentions are tagged and taken
/// out of the title, while every date and time phrase still parses as before.
final class QuickAddCourseTests: XCTestCase {
    private var cal: Calendar!
    /// Wednesday, August 26 2026, 10:00 AM America/Chicago.
    private var now: Date!
    private let known = ["BUAD312", "CLUBS", "CSCI113", "ECON351", "SAMMY", "WRIT150"]
    private let twoBuads = ["BUAD112", "BUAD312", "ECON351"]

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
        now = date(2026, 8, 26, 10, 0)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func parse(_ input: String, _ courses: [String]? = nil) -> QuickAddParse {
        QuickAddParser.parse(input, now: now, calendar: cal, knownCourses: courses ?? known)
    }

    func test_subjectWordWithConnector_andWeekday() {
        let r = parse("do homework in econ friday")
        XCTAssertEqual(r.title, "do homework")
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.dueDate, date(2026, 8, 28, 23, 59))
    }

    func test_ofSubject_dueWeekday() {
        let r = parse("read chapter 7 of econ due monday")
        XCTAssertEqual(r.title, "read chapter 7")
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.dueDate, date(2026, 8, 31, 23, 59))
    }

    func test_subjectWithSlashDate() {
        let r = parse("Econ test 10/12")
        XCTAssertEqual(r.title, "test")
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.dueDate, date(2026, 10, 12, 23, 59))
    }

    func test_fullNameAtStart() {
        let r = parse("buad312 midterm project")
        XCTAssertEqual(r.title, "midterm project")
        XCTAssertEqual(r.course, "BUAD312")
    }

    func test_numberAlone_withTime() {
        let r = parse("351 problem set fri 5pm")
        XCTAssertEqual(r.title, "problem set")
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.dueDate, date(2026, 8, 28, 17, 0))
    }

    func test_smallNumbersStayInTheTitle() {
        let r = parse("hw 6 csci")
        XCTAssertEqual(r.title, "hw 6")
        XCTAssertEqual(r.course, "CSCI113")
    }

    func test_typo() {
        let r = parse("ecom hw")
        XCTAssertEqual(r.title, "hw")
        XCTAssertEqual(r.course, "ECON351")
    }

    func test_atNumber_isATime_notACourse() {
        let r = parse("quiz at 312")
        XCTAssertEqual(r.title, "quiz")
        XCTAssertNil(r.course)
        XCTAssertTrue(r.hasExplicitTime)
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 15, 12))
    }

    func test_ambiguousSubject_tagsNothing_andFlagsIt() {
        let r = parse("BUAD Midterm project", twoBuads)
        XCTAssertEqual(r.title, "BUAD Midterm project")
        XCTAssertNil(r.course)
        XCTAssertTrue(r.hasAmbiguousCourse)
    }

    func test_ambiguousSubjectPlusNumber_resolves() {
        let r = parse("buad 112 case write-up", twoBuads)
        XCTAssertEqual(r.title, "case write-up")
        XCTAssertEqual(r.course, "BUAD112")
        XCTAssertFalse(r.hasAmbiguousCourse)
    }

    func test_onlyACourseWord_keepsItAsTheTitle() {
        let r = parse("econ friday")
        XCTAssertEqual(r.title, "econ")
        XCTAssertEqual(r.course, "ECON351")
    }

    func test_everydayWord_isNotAClass() {
        let r = parse("write cover letter")
        XCTAssertEqual(r.title, "write cover letter")
        XCTAssertNil(r.course)
    }

    // MARK: - #tags

    func test_hashtag_resolvesToTheKnownCourse() {
        let r = parse("essay #econ")
        XCTAssertEqual(r.title, "essay")
        XCTAssertEqual(r.course, "ECON351")
    }

    func test_hashtag_unknownCourse_isKeptAsTyped() {
        let r = parse("essay #PSYCH101")
        XCTAssertEqual(r.title, "essay")
        XCTAssertEqual(r.course, "PSYCH101")
    }

    func test_hashtag_alsoClearsAPlainMentionOfTheSameCourse() {
        let r = parse("econ reading #ECON351")
        XCTAssertEqual(r.title, "reading")
        XCTAssertEqual(r.course, "ECON351")
    }

    func test_hashtag_ambiguous_tagsNothing() {
        let r = parse("essay #buad", twoBuads)
        XCTAssertEqual(r.title, "essay")
        XCTAssertNil(r.course)
        XCTAssertTrue(r.hasAmbiguousCourse)
    }

    // MARK: - No known courses

    func test_withoutKnownCourses_plainWordsAreLeftAlone() {
        let r = QuickAddParser.parse("econ homework fri", now: now, calendar: cal)
        XCTAssertEqual(r.title, "econ homework")
        XCTAssertNil(r.course)
        XCTAssertFalse(r.hasAmbiguousCourse)
    }
}
