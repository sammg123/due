import XCTest
@testable import DueCore

final class NoteGroundingTests: XCTestCase {
    private let transcript = """
    The expected value is the weighted sum of possible outcomes. Imagine an investment
    with a fifty percent chance of paying 310 dollars and a fifty percent chance of 290.
    The variance measures how risky or volatile the investment is. Correlation between
    variables does not imply causation, like wildfires and ice cream sales.
    """

    func testFaithfulRewriteSharesVocabulary() {
        let output = """
        ## Expected Value
        - **Expected value** = weighted sum of possible outcomes.
        - Example investment: 50% chance of `310`, 50% chance of `290`.
        ## Variance and Correlation
        - **Variance** measures how volatile an investment is.
        - **Correlation** does not imply causation (wildfires vs ice cream sales).
        """
        XCTAssertTrue(NoteGrounding.sharesVocabulary(output: output, input: transcript))
    }

    func testFabricatedContentIsRejected() {
        let fabricated = """
        ## Introduction to Data Science
        - Data Science is an interdisciplinary field using algorithms and systems.
        - Key tools: Python, Pandas, NumPy, Hadoop, Spark.
        - Challenges include data quality, complexity, and ethics.
        """
        XCTAssertFalse(NoteGrounding.sharesVocabulary(output: fabricated, input: transcript))
    }

    func testShortInputsAlwaysPass() {
        XCTAssertTrue(NoteGrounding.sharesVocabulary(output: "anything at all", input: "## Lecture · Sep 2"))
        XCTAssertTrue(NoteGrounding.sharesVocabulary(output: "x", input: "short note"))
    }

    func testSubstanceRequiresNonHeadingContent() {
        XCTAssertFalse(NoteGrounding.hasSubstance("## Lecture · Sep 2, 2:04 PM"))
        XCTAssertFalse(NoteGrounding.hasSubstance("## A\n\n### B\n\n---"))
        XCTAssertFalse(NoteGrounding.hasSubstance("ok."))
        XCTAssertTrue(NoteGrounding.hasSubstance(transcript))
    }
}
