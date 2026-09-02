import XCTest
@testable import DueCore

final class MathPrettifierTests: XCTestCase {
    func testSqrtBecomesRadical() {
        XCTAssertEqual(MathPrettifier.pretty("sqrt(310)"), "√(310)")
        XCTAssertEqual(MathPrettifier.pretty("1/2 * sqrt(600)"), "1/2 · √(600)")
    }

    func testSimpleExponentsBecomeSuperscripts() {
        XCTAssertEqual(MathPrettifier.pretty("x^2"), "x²")
        XCTAssertEqual(MathPrettifier.pretty("2^10"), "2¹⁰")
        XCTAssertEqual(MathPrettifier.pretty("x^n"), "xⁿ")
        XCTAssertEqual(MathPrettifier.pretty("x^-2"), "x⁻²")
    }

    func testUnmappableExponentGroupsStayButInnerOnesConvert() {
        // The outer (-x^2/2) group contains '/', so it stays literal; the inner ^2 converts.
        XCTAssertEqual(MathPrettifier.pretty("e^(-x^2/2)"), "e^(-x²/2)")
    }

    func testMultiplicationDotAndComparisons() {
        XCTAssertEqual(MathPrettifier.pretty("(0.5 * 310) + (0.5 * 290) = 300"), "(0.5 · 310) + (0.5 · 290) = 300")
        XCTAssertEqual(MathPrettifier.pretty("Q1 - 1.5*IQR"), "Q1 - 1.5·IQR")
        XCTAssertEqual(MathPrettifier.pretty("x <= 5 and y >= 2 and z != 3"), "x ≤ 5 and y ≥ 2 and z ≠ 3")
        XCTAssertEqual(MathPrettifier.pretty("+/- 2"), "± 2")
    }

    func testGreekWordsConvertOnWordBoundariesOnly() {
        XCTAssertEqual(MathPrettifier.pretty("2*pi*r"), "2·π·r")
        XCTAssertEqual(MathPrettifier.pretty("pick a pi"), "pick a π")
        XCTAssertEqual(MathPrettifier.pretty("spice"), "spice")
        XCTAssertEqual(MathPrettifier.pretty("sigma / mu"), "σ / μ")
    }

    func testPlainTextIsUntouched() {
        XCTAssertEqual(MathPrettifier.pretty("IQR = Q3 - Q1"), "IQR = Q3 - Q1")
        XCTAssertEqual(MathPrettifier.pretty(""), "")
    }
}
