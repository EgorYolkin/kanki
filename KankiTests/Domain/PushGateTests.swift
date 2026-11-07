import XCTest

@testable import Kanki

final class PushGateTests: XCTestCase {
    func testSecondBeginWhileRunningRequestsAnotherPush() {
        var gate = PushGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin(), "Второй пуш не должен стартовать параллельно")
        XCTAssertTrue(gate.isRunning)

        XCTAssertTrue(gate.finishAndNeedsAnother(), "Накопленная правка требует повтора")
        XCTAssertTrue(gate.isRunning)

        XCTAssertFalse(gate.finishAndNeedsAnother(), "Очередь пуста — полёт завершён")
        XCTAssertFalse(gate.isRunning)
    }

    func testBeginAfterIdleRunsAgain() {
        var gate = PushGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.finishAndNeedsAnother())
        XCTAssertTrue(gate.begin(), "После завершения новый пуш разрешён")
    }
}
