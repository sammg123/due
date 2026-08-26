import XCTest
@testable import DueCore

final class QuickAddParserTests: XCTestCase {
    private var cal: Calendar!
    /// Wednesday, August 26 2026, 10:00 AM America/Chicago.
    private var now: Date!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        cal = c
        now = date(2026, 8, 26, 10, 0)
        XCTAssertEqual(cal.component(.weekday, from: now), 4, "sanity check: Aug 26 2026 must be Wednesday")
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func parse(_ input: String) -> QuickAddParse {
        QuickAddParser.parse(input, now: now, calendar: cal)
    }

    // MARK: - Weekday + time combo

    func test_parse_titleWeekdayAndTime() {
        let r = parse("pset 4 fri 5pm")
        XCTAssertEqual(r.title, "pset 4")
        XCTAssertEqual(r.dueDate, date(2026, 8, 28, 17, 0))
        XCTAssertTrue(r.hasExplicitTime)
    }

    func test_parse_fullComboWithCourseAndEstimate() {
        let r = parse("problem set 4 fri 5pm #CS225 ~2h")
        XCTAssertEqual(r.title, "problem set 4")
        XCTAssertEqual(r.dueDate, date(2026, 8, 28, 17, 0))
        XCTAssertEqual(r.course, "CS225")
        XCTAssertEqual(r.estimateMinutes, 120)
        XCTAssertTrue(r.hasExplicitTime)
    }

    func test_parse_numberInTitleIsNotMisreadAsTime() {
        // "4" has no am/pm suffix and no at/@ prefix, so it must stay part of the title, not become a time.
        let r = parse("pset 4")
        XCTAssertEqual(r.title, "pset 4")
        XCTAssertNil(r.dueDate)
        XCTAssertFalse(r.hasExplicitTime)
    }

    // MARK: - Relative days

    func test_parse_tomorrow_dueEndOfDayNoExplicitTime() {
        let r = parse("essay due tomorrow")
        XCTAssertEqual(r.title, "essay")
        XCTAssertEqual(r.dueDate, date(2026, 8, 27, 23, 59))
        XCTAssertFalse(r.hasExplicitTime)
    }

    func test_parse_tonight_dueEndOfToday() {
        let r = parse("read ch 3 tonight")
        XCTAssertEqual(r.title, "read ch 3")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 23, 59))
    }

    func test_parse_noDateKeyword_dueDateIsNil() {
        let r = parse("lab report")
        XCTAssertEqual(r.title, "lab report")
        XCTAssertNil(r.dueDate)
    }

    func test_parse_sameWeekdayAsToday_resolvesToToday() {
        let r = parse("quiz wed")
        XCTAssertEqual(r.title, "quiz")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 23, 59))
    }

    func test_parse_nextWed_rollsToFollowingWeek() {
        let r = parse("quiz next wed")
        XCTAssertEqual(r.title, "quiz")
        XCTAssertEqual(r.dueDate, date(2026, 9, 2, 23, 59))
    }

    func test_parse_nextFri_rollsPastThisWeeksFriday() {
        // The upcoming Friday (8/28) is still within the current calendar week (Sun 8/23 - Sat 8/29),
        // so "next fri" rolls all the way to the Friday of the following week.
        let r = parse("next fri")
        XCTAssertEqual(r.dueDate, date(2026, 9, 4, 23, 59))
        XCTAssertEqual(r.title, "")
    }

    func test_parse_inNDays() {
        let r = parse("assignment in 3 days")
        XCTAssertEqual(r.title, "assignment")
        XCTAssertEqual(r.dueDate, date(2026, 8, 29, 23, 59))
    }

    func test_parse_inNWeeks() {
        let r = parse("trip in 2 weeks")
        XCTAssertEqual(r.title, "trip")
        XCTAssertEqual(r.dueDate, date(2026, 9, 9, 23, 59))
    }

    func test_parse_eow_resolvesToUpcomingFriday() {
        let r = parse("trip eow")
        XCTAssertEqual(r.title, "trip")
        XCTAssertEqual(r.dueDate, date(2026, 8, 28, 23, 59))
    }

    // MARK: - Absolute dates

    func test_parse_monthNameAndDay() {
        let r = parse("final dec 8")
        XCTAssertEqual(r.title, "final")
        XCTAssertEqual(r.dueDate, date(2026, 12, 8, 23, 59))
    }

    func test_parse_numericMonthSlashDay_matchesMonthNameForm() {
        let r = parse("final 12/8")
        XCTAssertEqual(r.title, "final")
        XCTAssertEqual(r.dueDate, date(2026, 12, 8, 23, 59))
    }

    func test_parse_pastMonthDayThisYear_rollsToNextYear() {
        let r = parse("reg jan 5")
        XCTAssertEqual(r.title, "reg")
        XCTAssertEqual(r.dueDate, date(2027, 1, 5, 23, 59))
    }

    // MARK: - Time-only rollover

    func test_parse_bareAtHour_beforeSixReadsAsPM_todayWhenStillAhead() {
        let r = parse("meet at 5")
        XCTAssertEqual(r.title, "meet")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 17, 0)) // 5pm today, since now is 10am
        XCTAssertTrue(r.hasExplicitTime)
    }

    func test_parse_bareAtHour_pastNow_rollsToTomorrow() {
        let r = parse("call mom at 9")
        XCTAssertEqual(r.title, "call mom")
        XCTAssertEqual(r.dueDate, date(2026, 8, 27, 9, 0)) // 9am has already passed (now is 10am) -> tomorrow
        XCTAssertTrue(r.hasExplicitTime)
    }

    func test_parse_clockTimeWithMinutes_pmSuffix() {
        let r = parse("workout 5:30pm")
        XCTAssertEqual(r.title, "workout")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 17, 30))
    }

    func test_parse_militaryTime() {
        let r = parse("shift 17:00")
        XCTAssertEqual(r.title, "shift")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 17, 0))
    }

    func test_parse_noon() {
        let r = parse("lunch noon")
        XCTAssertEqual(r.title, "lunch")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 12, 0))
    }

    func test_parse_midnight_resolvesToElevenFiftyNinePM() {
        // The parser's "midnight" is treated as end-of-day (23:59), matching the app's due-by-end-of-day
        // semantics used elsewhere (DueLogic.endOfDay), not literal 00:00.
        let r = parse("party midnight")
        XCTAssertEqual(r.title, "party")
        XCTAssertEqual(r.dueDate, date(2026, 8, 26, 23, 59))
    }

    // MARK: - Course + estimate tokens

    func test_parse_courseTag_setsCourseAndStripsToken() {
        let r = parse("read notes #CS225")
        XCTAssertEqual(r.title, "read notes")
        XCTAssertEqual(r.course, "CS225")
        XCTAssertNil(r.dueDate)
    }

    func test_parse_estimateMinutesOnly() {
        XCTAssertEqual(parse("task ~45m").estimateMinutes, 45)
    }

    func test_parse_estimateHourOnly() {
        XCTAssertEqual(parse("task ~1h").estimateMinutes, 60)
    }

    func test_parse_estimateFractionalHour() {
        XCTAssertEqual(parse("task ~1.5h").estimateMinutes, 90)
    }

    func test_parse_estimateHourPlusMinutesCombined() {
        XCTAssertEqual(parse("task ~1h30m").estimateMinutes, 90)
    }

    func test_parse_estimateWordedHours() {
        XCTAssertEqual(parse("task ~2 hours").estimateMinutes, 120)
    }

    // MARK: - Title cleanup

    func test_parse_titleCleanup_stripsTrailingDue() {
        XCTAssertEqual(parse("assignment due").title, "assignment")
    }

    func test_parse_titleCleanup_stripsTrailingBy() {
        XCTAssertEqual(parse("reading by").title, "reading")
    }

    func test_parse_titleCleanup_stripsTrailingAt() {
        XCTAssertEqual(parse("quiz at").title, "quiz")
    }

    func test_parse_titleCleanup_stripsTrailingOn() {
        XCTAssertEqual(parse("notes on").title, "notes")
    }

    func test_parse_titleCleanup_collapsesWhitespace() {
        XCTAssertEqual(parse("task    with   many     spaces").title, "task with many spaces")
    }

    // MARK: - offsetToWeekday (internal, direct)

    func test_offsetToWeekday_sameWeekdayNotNext_isZero() {
        XCTAssertEqual(QuickAddParser.offsetToWeekday(4, from: now, calendar: cal, next: false), 0) // Wed
    }

    func test_offsetToWeekday_sameWeekdayNext_rollsFullWeek() {
        XCTAssertEqual(QuickAddParser.offsetToWeekday(4, from: now, calendar: cal, next: true), 7) // next Wed
    }

    func test_offsetToWeekday_upcomingFridayNotNext() {
        XCTAssertEqual(QuickAddParser.offsetToWeekday(6, from: now, calendar: cal, next: false), 2) // Fri
    }

    func test_offsetToWeekday_nextFriday_rollsPastThisWeeksFriday() {
        XCTAssertEqual(QuickAddParser.offsetToWeekday(6, from: now, calendar: cal, next: true), 9) // next Fri
    }

    func test_offsetToWeekday_mondayAlreadyNextCalendarWeek_noExtraRoll() {
        // Upcoming Monday (8/31) already falls in the calendar week after now's (Sun 8/23-Sat 8/29),
        // so "next monday" needs no additional +7 beyond the naive upcoming occurrence.
        let plain = QuickAddParser.offsetToWeekday(2, from: now, calendar: cal, next: false)
        let next = QuickAddParser.offsetToWeekday(2, from: now, calendar: cal, next: true)
        XCTAssertEqual(plain, 5)
        XCTAssertEqual(next, 5)
    }
}
