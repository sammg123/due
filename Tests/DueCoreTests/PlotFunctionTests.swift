import XCTest
@testable import DueCore

final class PlotFunctionTests: XCTestCase {
    private func value(_ expr: String, at x: Double) -> Double? {
        PlotFunction.parse(expr)?.evaluate(at: x)
    }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(value("2 + 3 * 4", at: 0), 14)
        XCTAssertEqual(value("(2 + 3) * 4", at: 0), 20)
        XCTAssertEqual(value("2 ^ 3 ^ 2", at: 0), 512, "power is right-associative")
        XCTAssertEqual(value("10 / 4", at: 0), 2.5)
    }

    func testVariableAndUnaryMinus() {
        XCTAssertEqual(value("x^2", at: 3), 9)
        XCTAssertEqual(value("-x + 1", at: 2), -1)
        XCTAssertEqual(value("2x", at: 4), 8, "implicit multiplication")
        XCTAssertEqual(value("-x^2", at: 2), -4, "unary minus binds looser than power")
    }

    func testFunctionsAndConstants() throws {
        XCTAssertEqual(try XCTUnwrap(value("sin(pi/2)", at: 0)), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(value("exp(0)", at: 0)), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(value("sqrt(x)", at: 16)), 4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(value("abs(-3)", at: 0)), 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(value("ln(e)", at: 0)), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(value("e^(-x^2/2)", at: 0)), 1, accuracy: 1e-9)
    }

    func testInvalidExpressionsFailToParse() {
        XCTAssertNil(PlotFunction.parse(""))
        XCTAssertNil(PlotFunction.parse("2 +"))
        XCTAssertNil(PlotFunction.parse("foo(x)"))
        XCTAssertNil(PlotFunction.parse("x; import os"))
        XCTAssertNil(PlotFunction.parse("(x"))
    }

    func testDeeplyNestedParensFailGracefullyInsteadOfCrashing() {
        // A degenerate model output; without a depth cap this overflowed the stack.
        let deep = String(repeating: "(", count: 50_000) + "x" + String(repeating: ")", count: 50_000)
        XCTAssertNil(PlotFunction.parse(deep))
        // Reasonable nesting still parses.
        XCTAssertNotNil(PlotFunction.parse(String(repeating: "(", count: 30) + "x" + String(repeating: ")", count: 30)))
    }

    func testUndefinedValuesReturnNil() {
        XCTAssertNil(value("1 / x", at: 0))
        XCTAssertNil(value("sqrt(x)", at: -4))
        XCTAssertNil(value("ln(x)", at: 0))
    }
}
