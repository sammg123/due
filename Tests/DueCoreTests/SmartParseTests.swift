import XCTest
@testable import DueCore

final class SmartParseTests: XCTestCase {
    private var cal: Calendar!
    private var now: Date!
    private let known = ["WRIT150", "CSCI113", "MATH241"]

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
        now = date(2026, 8, 26, 10, 0) // Wednesday
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    // MARK: - String initializer: day / time

    func test_init_validDateAndTime_parseIntoComponents() {
        // Arrange / Act
        let r = SmartParseResult(title: "Essay", dateString: "2026-08-27", timeString: "12:30", course: "", estimateMinutes: 0, knownCourses: [])
        // Assert
        XCTAssertEqual(r.day, DateComponents(year: 2026, month: 8, day: 27))
        XCTAssertEqual(r.time, DateComponents(hour: 12, minute: 30))
    }

    func test_init_blankOrUnparseableDateString_dayIsNil() {
        XCTAssertNil(SmartParseResult(title: "A", dateString: "", timeString: "12:30", course: "", estimateMinutes: 0, knownCourses: []).day)
        XCTAssertNil(SmartParseResult(title: "A", dateString: "tomorrow", timeString: "12:30", course: "", estimateMinutes: 0, knownCourses: []).day)
    }

    func test_init_dateStringOutOfRange_dayIsNil() {
        // Month 13 and day 40 are both out of range.
        XCTAssertNil(SmartParseResult(title: "A", dateString: "2026-13-40", timeString: "12:30", course: "", estimateMinutes: 0, knownCourses: []).day)
    }

    func test_init_blankOrOutOfRangeTimeString_timeIsNil() {
        XCTAssertNil(SmartParseResult(title: "A", dateString: "2026-08-27", timeString: "", course: "", estimateMinutes: 0, knownCourses: []).time)
        XCTAssertNil(SmartParseResult(title: "A", dateString: "2026-08-27", timeString: "25:99", course: "", estimateMinutes: 0, knownCourses: []).time)
    }

    // MARK: - String initializer: estimateMinutes

    func test_init_estimateMinutesZeroIsNil_positiveIsKept() {
        let zero = SmartParseResult(title: "A", dateString: "", timeString: "", course: "", estimateMinutes: 0, knownCourses: [])
        let positive = SmartParseResult(title: "A", dateString: "", timeString: "", course: "", estimateMinutes: 45, knownCourses: [])
        XCTAssertNil(zero.estimateMinutes)
        XCTAssertEqual(positive.estimateMinutes, 45)
    }

    // MARK: - String initializer: title

    func test_init_whitespaceOnlyTitleIsNil_nonEmptyTitleIsTrimmed() {
        let blank = SmartParseResult(title: "   ", dateString: "", timeString: "", course: "", estimateMinutes: 0, knownCourses: [])
        let padded = SmartParseResult(title: "  Essay  ", dateString: "", timeString: "", course: "", estimateMinutes: 0, knownCourses: [])
        XCTAssertNil(blank.title)
        XCTAssertEqual(padded.title, "Essay")
    }

    // MARK: - matchCourse

    func test_matchCourse_exactCaseAndSpaceInsensitive() {
        XCTAssertEqual(SmartParseResult.matchCourse("writ 150", known: known), "WRIT150")
    }

    func test_matchCourse_lettersPrefix_shortInputMatches() {
        XCTAssertEqual(SmartParseResult.matchCourse("writ", known: known), "WRIT150")
    }

    func test_matchCourse_lettersPrefix_longerInputMatches() {
        // "writing" has more letters than "writ150"'s letter-prefix ("writ"); this should still resolve
        // to WRIT150 per the documented "letters-only prefix" behavior.
        XCTAssertEqual(SmartParseResult.matchCourse("writing", known: known), "WRIT150")
    }

    func test_matchCourse_containedTermMatchesKnownCourse() {
        XCTAssertEqual(SmartParseResult.matchCourse("csci", known: known), "CSCI113")
    }

    func test_matchCourse_unknownCourseReturnedAsTyped() {
        XCTAssertEqual(SmartParseResult.matchCourse("PSYCH 101", known: known), "PSYCH 101")
    }

    func test_matchCourse_emptyIsNil() {
        XCTAssertNil(SmartParseResult.matchCourse("   ", known: known))
    }

    // MARK: - merging: title

    func test_merging_smartTitleOverridesRegexTitle() {
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 17, 0), course: "REGEXCOURSE", estimateMinutes: 30, hasExplicitTime: true)
        let smart = SmartParseResult(title: "Smart Title")
        XCTAssertEqual(base.merging(smart, now: now, calendar: cal).title, "Smart Title")
    }

    func test_merging_regexTitleSurvives_whenSmartTitleNil() {
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 17, 0), course: "REGEXCOURSE", estimateMinutes: 30, hasExplicitTime: true)
        let smart = SmartParseResult()
        XCTAssertEqual(base.merging(smart, now: now, calendar: cal).title, "Regex Title")
    }

    // MARK: - merging: day + time combinations

    func test_merging_regexDayAndTime_winOverSmartDayAndTime() {
        // Arrange: regex read "fri 5pm" exactly; the model disagrees on both. Regex is authoritative.
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 17, 0), hasExplicitTime: true)
        let smart = SmartParseResult(day: DateComponents(year: 2026, month: 9, day: 10), time: DateComponents(hour: 14, minute: 15))
        // Act
        let merged = base.merging(smart, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(merged.dueDate, date(2026, 8, 27, 17, 0))
        XCTAssertTrue(merged.hasExplicitTime)
    }

    func test_merging_smartDayIgnored_whenRegexFoundADay() {
        // Arrange: the model is known to get "next fri" wrong; regex found the day, so keep it.
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 9, 4, 23, 59), hasExplicitTime: false)
        let smart = SmartParseResult(day: DateComponents(year: 2026, month: 9, day: 3))
        // Act
        let merged = base.merging(smart, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(merged.dueDate, date(2026, 9, 4, 23, 59))
        XCTAssertFalse(merged.hasExplicitTime)
    }

    func test_merging_smartDayUsed_whenRegexFoundNoDay() {
        // Arrange: "end of the month" is not a regex phrase; the model's day fills the gap.
        let base = QuickAddParse(title: "Regex Title", dueDate: nil, hasExplicitTime: false)
        let smart = SmartParseResult(day: DateComponents(year: 2026, month: 8, day: 31), time: DateComponents(hour: 14, minute: 15))
        // Act
        let merged = base.merging(smart, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(merged.dueDate, date(2026, 8, 31, 14, 15))
        XCTAssertTrue(merged.hasExplicitTime)
    }

    func test_merging_smartDayOnly_defaultsToElevenFiftyNinePM() {
        // Arrange: regex had no date and no explicit time at all.
        let base = QuickAddParse(title: "Regex Title", dueDate: nil, hasExplicitTime: false)
        let smart = SmartParseResult(day: DateComponents(year: 2026, month: 10, day: 5))
        // Act
        let merged = base.merging(smart, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(merged.dueDate, date(2026, 10, 5, 23, 59))
        XCTAssertFalse(merged.hasExplicitTime)
    }

    func test_merging_smartTimeOnly_withRegexDate_usesRegexDayAtSmartTime() {
        // Arrange: regex resolved a day with no explicit time ("tomorrow" -> 11:59 PM).
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 23, 59), hasExplicitTime: false)
        let smart = SmartParseResult(time: DateComponents(hour: 9, minute: 15))
        // Act
        let merged = base.merging(smart, now: now, calendar: cal)
        // Assert
        XCTAssertEqual(merged.dueDate, date(2026, 8, 27, 9, 15))
        XCTAssertTrue(merged.hasExplicitTime)
    }

    func test_merging_smartTimeOnly_noRegexDate_todayWhenStillAhead() {
        let base = QuickAddParse(title: "Regex Title", dueDate: nil, hasExplicitTime: false)
        let smart = SmartParseResult(time: DateComponents(hour: 18, minute: 0)) // 6pm, now is 10am
        let merged = base.merging(smart, now: now, calendar: cal)
        XCTAssertEqual(merged.dueDate, date(2026, 8, 26, 18, 0))
        XCTAssertTrue(merged.hasExplicitTime)
    }

    func test_merging_smartTimeOnly_noRegexDate_tomorrowWhenAlreadyPassed() {
        let base = QuickAddParse(title: "Regex Title", dueDate: nil, hasExplicitTime: false)
        let smart = SmartParseResult(time: DateComponents(hour: 8, minute: 0)) // 8am, now is 10am
        let merged = base.merging(smart, now: now, calendar: cal)
        XCTAssertEqual(merged.dueDate, date(2026, 8, 27, 8, 0))
        XCTAssertTrue(merged.hasExplicitTime)
    }

    func test_merging_nothingFromSmart_regexResultUnchanged() {
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 17, 0), course: "REGEXCOURSE", estimateMinutes: 30, hasExplicitTime: true)
        let smart = SmartParseResult()
        XCTAssertEqual(base.merging(smart, now: now, calendar: cal), base)
    }

    // MARK: - merging: course + estimate

    func test_merging_regexCourseBeatsTheModel_estimateStillFromTheModel() {
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 17, 0), course: "WRIT150", estimateMinutes: 30, hasExplicitTime: true)
        let smart = SmartParseResult(course: "CSCI113", estimateMinutes: 77)
        let merged = base.merging(smart, now: now, calendar: cal, knownCourses: known)
        XCTAssertEqual(merged.course, "WRIT150")
        XCTAssertEqual(merged.estimateMinutes, 77)
    }

    func test_merging_modelCourseFillsIn_whenRegexFoundNone_andItIsKnown() {
        let base = QuickAddParse(title: "essay")
        let merged = base.merging(SmartParseResult(course: "CSCI113"), now: now, calendar: cal, knownCourses: known)
        XCTAssertEqual(merged.course, "CSCI113")
    }

    func test_merging_modelCourseThatIsNotKnown_isDropped() {
        let base = QuickAddParse(title: "essay")
        let merged = base.merging(SmartParseResult(course: "PSYCH 101"), now: now, calendar: cal, knownCourses: known)
        XCTAssertNil(merged.course)
    }

    func test_merging_modelCannotPickACourse_whenTheTextWasAmbiguous() {
        let base = QuickAddParse(title: "BUAD midterm", hasAmbiguousCourse: true)
        let merged = base.merging(SmartParseResult(course: "BUAD312"), now: now, calendar: cal, knownCourses: ["BUAD112", "BUAD312"])
        XCTAssertNil(merged.course)
    }

    func test_merging_modelTitle_hasTheCourseMentionStripped() {
        let base = QuickAddParse(title: "homework", course: "WRIT150")
        let merged = base.merging(SmartParseResult(title: "homework for writ 150"), now: now, calendar: cal, knownCourses: known)
        XCTAssertEqual(merged.title, "homework")
    }

    func test_merging_modelTitleThatIsOnlyTheCourse_isKept() {
        let base = QuickAddParse(title: "writ", course: "WRIT150")
        let merged = base.merging(SmartParseResult(title: "writ"), now: now, calendar: cal, knownCourses: known)
        XCTAssertEqual(merged.title, "writ")
    }

    func test_merging_regexCourseAndEstimateSurvive_whenSmartNil() {
        let base = QuickAddParse(title: "Regex Title", dueDate: date(2026, 8, 27, 17, 0), course: "REGEXCOURSE", estimateMinutes: 30, hasExplicitTime: true)
        let smart = SmartParseResult()
        let merged = base.merging(smart, now: now, calendar: cal)
        XCTAssertEqual(merged.course, "REGEXCOURSE")
        XCTAssertEqual(merged.estimateMinutes, 30)
    }
}
