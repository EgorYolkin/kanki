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

    func testFetchStartedBeforePushCannotApplyAfterAcknowledgement() {
        var gate = PushGate()
        let fetchGeneration = gate.generation
        XCTAssertTrue(gate.canApplyFetch(startedAt: fetchGeneration))

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.canApplyFetch(startedAt: fetchGeneration))
        XCTAssertFalse(gate.finishAndNeedsAnother())

        XCTAssertFalse(gate.canApplyFetch(startedAt: fetchGeneration))
        XCTAssertTrue(gate.canApplyFetch(startedAt: gate.generation))
    }

    func testEditBeforeDebouncePreservesUnacknowledgedChangeAndRepeatsPush() {
        var gate = PushGate()
        gate.markChanged()
        XCTAssertTrue(gate.begin())
        let sentGeneration = gate.generation

        // Сохранение B произошло, но второй begin из debounce ещё не вызван.
        gate.markChanged()

        XCTAssertFalse(gate.isCurrent(sentGeneration), "Ответ на A не подтверждает B")
        XCTAssertTrue(gate.finishAndNeedsAnother())
        XCTAssertTrue(gate.isRunning, "Сохранённая B отправляется без ожидания таймера")
        XCTAssertFalse(gate.finishAndNeedsAnother())
    }

    func testEditAndRevertStillInvalidateEarlierResponse() {
        var gate = PushGate()
        let fetchGeneration = gate.generation

        gate.markChanged()
        gate.markChanged()

        XCTAssertFalse(gate.canApplyFetch(startedAt: fetchGeneration))
        XCTAssertFalse(gate.isCurrent(fetchGeneration))
    }

    func testManualSyncCannotOverlapPushAndInvalidatesEarlierFetch() {
        var gate = PushGate()
        let fetchGeneration = gate.generation
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.beginManualSync())
        XCTAssertFalse(gate.finishAndNeedsAnother())

        XCTAssertTrue(gate.beginManualSync())
        XCTAssertFalse(gate.beginManualSync())
        XCTAssertFalse(gate.begin())
        XCTAssertFalse(gate.canApplyFetch(startedAt: gate.generation))
        let manualGeneration = gate.generation
        gate.markChanged()
        XCTAssertFalse(gate.isCurrent(manualGeneration), "Ручной push/pull не подтверждает новую правку")
        gate.finishManualSync()

        XCTAssertFalse(gate.canApplyFetch(startedAt: fetchGeneration))
        XCTAssertTrue(gate.canApplyFetch(startedAt: gate.generation))
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.finishAndNeedsAnother(), "Отклонённый авто-push не оставляет ложный повтор")
    }
}
