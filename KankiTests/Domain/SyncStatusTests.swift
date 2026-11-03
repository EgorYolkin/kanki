import XCTest
@testable import Kanki

final class SyncStatusTests: XCTestCase {
    func testHiddenWithoutConfiguredServer() {
        let text = SyncStatus.text(
            isConfigured: false,
            hasConflict: false,
            lastSyncFailed: false,
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertNil(text)
    }

    func testConflictTakesPriority() {
        let text = SyncStatus.text(
            isConfigured: true,
            hasConflict: true,
            lastSyncFailed: true,
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Конфликт ревизий — разрешите в настройках")
    }

    func testNetworkFailureIsReported() {
        let text = SyncStatus.text(
            isConfigured: true,
            hasConflict: false,
            lastSyncFailed: true,
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Сервер недоступен — повтор при следующем открытии")
    }

    func testUnsyncedChangesAreVisible() {
        let text = SyncStatus.text(
            isConfigured: true,
            hasConflict: false,
            lastSyncFailed: false,
            hasUnsyncedChanges: true,
            knownRevision: 12
        )

        XCTAssertEqual(text, "Есть неотправленные изменения")
    }

    func testSyncedStateShowsRevision() {
        let text = SyncStatus.text(
            isConfigured: true,
            hasConflict: false,
            lastSyncFailed: false,
            hasUnsyncedChanges: false,
            knownRevision: 32
        )

        XCTAssertEqual(text, "Синхронизировано, ревизия 32")
    }

    func testConfiguredButNeverSynced() {
        let text = SyncStatus.text(
            isConfigured: true,
            hasConflict: false,
            lastSyncFailed: false,
            hasUnsyncedChanges: false,
            knownRevision: 0
        )

        XCTAssertEqual(text, "Синхронизация ещё не выполнялась")
    }
}
