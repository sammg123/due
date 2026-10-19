import XCTest
@testable import DueCore

final class CourseMatcherTests: XCTestCase {
    /// Sam's courses, the case the matcher was built for.
    private let known = ["BUAD312", "CLUBS", "CSCI113", "ECON351", "SAMMY", "WRIT150"]
    private let twoBuads = ["BUAD112", "BUAD312", "ECON351"]

    private func resolve(_ token: String, _ courses: [String]? = nil) -> CourseMatcher.Resolution {
        CourseMatcher.resolve(token, known: courses ?? known)
    }

    // MARK: - resolve: full names

    func test_resolve_fullName_isCaseInsensitive_andIgnoresAHashtag() {
        XCTAssertEqual(resolve("buad312"), .course("BUAD312"))
        XCTAssertEqual(resolve("BUAD312"), .course("BUAD312"))
        XCTAssertEqual(resolve("#BUAD312"), .course("BUAD312"))
        XCTAssertEqual(resolve("Econ351"), .course("ECON351"))
    }

    func test_resolve_fullName_matchesAKnownCourseWrittenWithASpace() {
        XCTAssertEqual(resolve("cs225", ["CS 225"]), .course("CS 225"))
    }

    // MARK: - resolve: numbers

    func test_resolve_courseNumberAlone_isThatCourse() {
        XCTAssertEqual(resolve("351"), .course("ECON351"))
        XCTAssertEqual(resolve("312"), .course("BUAD312"))
        XCTAssertEqual(resolve("113"), .course("CSCI113"))
        XCTAssertEqual(resolve("112", twoBuads), .course("BUAD112"))
    }

    func test_resolve_numberSharedByTwoCourses_isAmbiguous() {
        XCTAssertEqual(resolve("312", ["BUAD312", "MATH312"]), .ambiguous(["BUAD312", "MATH312"]))
    }

    func test_resolve_unknownOrShortNumbers_matchNothing() {
        XCTAssertEqual(resolve("999"), .none)
        XCTAssertEqual(resolve("6"), .none)
        XCTAssertEqual(resolve("11"), .none)
        XCTAssertEqual(resolve("12", ["CS12"]), .none)
    }

    // MARK: - resolve: subject words

    func test_resolve_subjectWord_isThatCourse_whenUnique() {
        XCTAssertEqual(resolve("econ"), .course("ECON351"))
        XCTAssertEqual(resolve("ECON"), .course("ECON351"))
        XCTAssertEqual(resolve("csci"), .course("CSCI113"))
        XCTAssertEqual(resolve("writ"), .course("WRIT150"))
        XCTAssertEqual(resolve("buad"), .course("BUAD312"))
    }

    func test_resolve_subjectSharedByTwoCourses_isAmbiguous() {
        XCTAssertEqual(resolve("buad", twoBuads), .ambiguous(["BUAD112", "BUAD312"]))
    }

    func test_resolve_subjectWithACourseSuffix_matches() {
        XCTAssertEqual(resolve("economics"), .course("ECON351"))
        XCTAssertEqual(resolve("econs"), .course("ECON351"))
        XCTAssertEqual(resolve("economy"), .course("ECON351"))
        XCTAssertEqual(resolve("writing"), .course("WRIT150"))
    }

    func test_resolve_everydayWordsThatStartWithASubject_doNotMatch() {
        XCTAssertEqual(resolve("write"), .none)
        XCTAssertEqual(resolve("written"), .none)
        XCTAssertEqual(resolve("writer"), .none)
    }

    func test_resolve_threeLetterPrefixOfASubject_matches() {
        XCTAssertEqual(resolve("eco"), .course("ECON351"))
        XCTAssertEqual(resolve("csc"), .course("CSCI113"))
        XCTAssertEqual(resolve("ec"), .none)
    }

    func test_resolve_commonShortWords_neverMatchAsPrefixes() {
        XCTAssertEqual(resolve("his", ["HIST101"]), .none)
        XCTAssertEqual(resolve("the", ["THEA200"]), .none)
        XCTAssertEqual(resolve("hist", ["HIST101"]), .course("HIST101"))
    }

    // MARK: - resolve: typos

    func test_resolve_oneNeighboringKeyTypo_matches() {
        XCTAssertEqual(resolve("ecom"), .course("ECON351")) // n -> m
        XCTAssertEqual(resolve("ecpn"), .course("ECON351")) // o -> p
        XCTAssertEqual(resolve("csco"), .course("CSCI113")) // i -> o
    }

    func test_resolve_swappedAdjacentLetters_match() {
        XCTAssertEqual(resolve("wirt"), .course("WRIT150"))
        XCTAssertEqual(resolve("ecno"), .course("ECON351"))
    }

    func test_resolve_realWordsOneLetterAway_doNotMatch() {
        XCTAssertEqual(resolve("icon"), .none) // e and i are not neighbors
        XCTAssertEqual(resolve("wait"), .none)
        XCTAssertEqual(resolve("quad"), .none)
    }

    func test_resolve_typoAgainstTwoCourses_isAmbiguous() {
        XCTAssertEqual(resolve("buas", twoBuads), .ambiguous(["BUAD112", "BUAD312"]))
    }

    func test_resolve_anExactSubject_beatsATypoOfAnother() {
        XCTAssertEqual(resolve("ecom", ["ECON351", "ECOM101"]), .course("ECOM101"))
    }

    // MARK: - resolve: letter-only courses

    func test_resolve_letterOnlyCourse_wholeWordWithPluralTolerance() {
        XCTAssertEqual(resolve("clubs"), .course("CLUBS"))
        XCTAssertEqual(resolve("Club"), .course("CLUBS"))
        XCTAssertEqual(resolve("sammy"), .course("SAMMY"))
        XCTAssertEqual(resolve("sam"), .none)
        XCTAssertEqual(resolve("clu"), .none)
        XCTAssertEqual(resolve("clubz"), .none)
    }

    // MARK: - resolve: tokens the date parser owns

    func test_resolve_datesTimesAndGluedWords_matchNothing() {
        XCTAssertEqual(resolve("10/12"), .none)
        XCTAssertEqual(resolve("5pm"), .none)
        XCTAssertEqual(resolve("hw6"), .none)
        XCTAssertEqual(resolve("econ's"), .none)
        XCTAssertEqual(resolve(""), .none)
    }

    func test_resolve_noKnownCourses_matchesNothing() {
        XCTAssertEqual(resolve("econ", []), .none)
    }

    // MARK: - extract

    func test_extract_stripsTheMentionAndItsConnector() {
        let r = CourseMatcher.extract(from: "do homework in econ", known: known)
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.text, "do homework")
        XCTAssertFalse(r.isAmbiguous)
    }

    func test_extract_fullNameAtTheStart() {
        let r = CourseMatcher.extract(from: "buad312 midterm project", known: known)
        XCTAssertEqual(r.course, "BUAD312")
        XCTAssertEqual(r.text, "midterm project")
    }

    func test_extract_subjectAndNumberSplitBySpace_isOneMention() {
        let r = CourseMatcher.extract(from: "BUAD 312 midterm", known: twoBuads)
        XCTAssertEqual(r.course, "BUAD312")
        XCTAssertEqual(r.text, "midterm")
    }

    func test_extract_redundantMentionsOfTheSameCourse_allGo() {
        let r = CourseMatcher.extract(from: "econ reading for 351", known: known)
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.text, "reading")
    }

    func test_extract_ambiguousSubjectAlone_tagsNothing_andKeepsTheText() {
        let r = CourseMatcher.extract(from: "BUAD Midterm project", known: twoBuads)
        XCTAssertNil(r.course)
        XCTAssertTrue(r.isAmbiguous)
        XCTAssertEqual(r.text, "BUAD Midterm project")
    }

    func test_extract_numberSettlesAnAmbiguousSubject_andBothAreStripped() {
        let r = CourseMatcher.extract(from: "BUAD midterm 312", known: twoBuads)
        XCTAssertEqual(r.course, "BUAD312")
        XCTAssertFalse(r.isAmbiguous)
        XCTAssertEqual(r.text, "midterm")
    }

    func test_extract_numberBeatsASubjectWordForADifferentCourse() {
        let r = CourseMatcher.extract(from: "econ notes 312", known: known)
        XCTAssertEqual(r.course, "BUAD312")
        XCTAssertEqual(r.text, "econ notes")
    }

    func test_extract_courseWordAfterTheMention_isDropped() {
        let r = CourseMatcher.extract(from: "essay for econ class", known: known)
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.text, "essay")
    }

    func test_extract_onlyACourseWord_keepsItAsTheTitle() {
        let r = CourseMatcher.extract(from: "econ", known: known)
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.text, "econ")
    }

    func test_extract_numberAfterACountWord_isNotACourse() {
        let r = CourseMatcher.extract(from: "read page 351", known: known)
        XCTAssertNil(r.course)
        XCTAssertEqual(r.text, "read page 351")
    }

    func test_extract_numberBeforeAQuantityWord_isNotACourse() {
        let r = CourseMatcher.extract(from: "write 150 words reflection", known: known)
        XCTAssertNil(r.course)
        XCTAssertEqual(r.text, "write 150 words reflection")
    }

    func test_extract_phrasalVerbKeepsItsIn() {
        let r = CourseMatcher.extract(from: "turn in econ essay", known: known)
        XCTAssertEqual(r.course, "ECON351")
        XCTAssertEqual(r.text, "turn in essay")
    }

    func test_extract_keepsTheCasingOfTheRestOfTheTitle() {
        let r = CourseMatcher.extract(from: "Midterm PROJECT csci", known: known)
        XCTAssertEqual(r.text, "Midterm PROJECT")
    }

    func test_extract_nothingToFind_returnsTheTextCollapsed() {
        let r = CourseMatcher.extract(from: "  write   cover letter ", known: known)
        XCTAssertNil(r.course)
        XCTAssertFalse(r.isAmbiguous)
        XCTAssertEqual(r.text, "write cover letter")
    }

    // MARK: - strip

    func test_strip_removesMentionsOfTheGivenCourse() {
        XCTAssertEqual(CourseMatcher.strip("ECON351", from: "homework for econ", known: known), "homework")
        XCTAssertEqual(CourseMatcher.strip("BUAD312", from: "BUAD midterm", known: twoBuads), "midterm")
    }

    func test_strip_leavesMentionsOfOtherCourses() {
        XCTAssertEqual(CourseMatcher.strip("ECON351", from: "econ essay for writ", known: known), "essay for writ")
    }

    func test_strip_wouldEmptyTheTitle_keepsItInstead() {
        XCTAssertEqual(CourseMatcher.strip("ECON351", from: "econ", known: known), "econ")
    }
}
