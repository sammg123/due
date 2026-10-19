import XCTest
@testable import DueCore

@MainActor
final class DeferredActionTests: XCTestCase {
    func test_run_afterInstall_runsRightAway() {
        // Arrange
        let action = DeferredAction()
        var runs = 0
        action.install { runs += 1 }

        // Act
        action.run()
        action.run()

        // Assert
        XCTAssertEqual(runs, 2)
    }

    func test_run_beforeInstall_waitsAndRunsOnceOnInstall() {
        let action = DeferredAction()
        var runs = 0

        action.run()
        action.run() // a second early request still means one window, not two
        XCTAssertEqual(runs, 0)

        action.install { runs += 1 }

        XCTAssertEqual(runs, 1)
    }

    func test_install_withNothingWaiting_doesNotRun() {
        let action = DeferredAction()
        var runs = 0

        action.install { runs += 1 }

        XCTAssertEqual(runs, 0)
    }

    func test_reinstall_doesNotReplayAnAlreadyHandledRequest() {
        let action = DeferredAction()
        var first = 0
        var second = 0
        action.run()
        action.install { first += 1 }

        action.install { second += 1 }
        action.run()

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }
}
