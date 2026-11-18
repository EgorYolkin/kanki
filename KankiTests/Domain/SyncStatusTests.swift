import XCTest
@testable import Kanki

final class SyncStatusTests: XCTestCase {
    func testHiddenWithoutConfiguredServer() {
        let text = SyncStatus.text(
            isConfigured: false,
            problem: .conflict(currentRevision: 13),
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertNil(text)
    }

    func testConflictTakesPriority() {
        let conflict = SyncStatus.Problem(error: ServerError.conflict(currentRevision: 13))
        let problem = SyncStatus.retainingConflict(.unavailable, onFailure: .conflict(currentRevision: 13))
        XCTAssertEqual(conflict, problem)
        XCTAssertEqual(SyncStatus.retainingConflict(problem, onFailure: .unauthorized), problem)

        let text = SyncStatus.text(
            isConfigured: true,
            problem: problem,
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Конфликт ревизий — разрешите в настройках")
    }

    func testNetworkFailureIsReported() {
        let text = SyncStatus.text(
            isConfigured: true,
            problem: SyncStatus.Problem(error: URLError(.cannotConnectToHost)),
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Сервер недоступен — повтор при следующем открытии")
    }

    func testRejectedTokenBeatsDirtyAndKnownRevision() {
        let text = SyncStatus.text(
            isConfigured: true,
            problem: SyncStatus.Problem(error: ServerError.unauthorized),
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Токен отклонён — проверьте настройки сервера")
    }

    func testOtherFailuresDoNotClaimConflictOrUnavailability() {
        let errors: [Error] = [
            ServerError.http(status: 503), ServerError.decoding, ServerError.invalidResponse, CocoaError(.fileWriteUnknown)
        ]
        for error in errors {
            XCTAssertEqual(SyncStatus.Problem(error: error)?.text, "Не удалось синхронизировать — повтор при следующем открытии")
        }
    }

    func testLatestNonConflictFailureReplacesPreviousOne() {
        XCTAssertEqual(SyncStatus.retainingConflict(.unavailable, onFailure: .unauthorized), .unauthorized)
    }

    func testFailedSaveAfterFetchReplacesNetworkFailureWithoutConfirmingRevision() {
        let problem = SyncStatus.retainingConflict(.unavailable, onFailure: .localSaveFailed)
        let text = SyncStatus.text(
            isConfigured: true,
            problem: problem,
            hasUnsyncedChanges: false,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Снимок получен, но не сохранён на устройстве")
    }

    func testCancellationDoesNotBecomeAFailure() {
        XCTAssertNil(SyncStatus.Problem(error: CancellationError()))
        XCTAssertNil(SyncStatus.Problem(error: URLError(.cancelled)))
    }

    func testUnsyncedChangesAreVisible() {
        let text = SyncStatus.text(
            isConfigured: true,
            problem: nil,
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Есть неотправленные изменения")
    }

    func testSyncedStateShowsRevision() {
        let text = SyncStatus.text(
            isConfigured: true,
            problem: nil,
            hasUnsyncedChanges: false,
            knownRevision: 32
        )

        XCTAssertEqual(text, "Синхронизировано, ревизия 32")
    }

    func testConfiguredButNeverSynced() {
        let text = SyncStatus.text(
            isConfigured: true,
            problem: nil,
            hasUnsyncedChanges: false,
            knownRevision: 0
        )

        XCTAssertEqual(text, "Синхронизация ещё не выполнялась")
    }
}
