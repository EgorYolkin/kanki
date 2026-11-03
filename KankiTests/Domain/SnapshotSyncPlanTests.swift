import XCTest
@testable import Kanki

final class SnapshotSyncPlanTests: XCTestCase {
    func testMatchingRevisionsWithoutLocalChangesAreNoop() {
        let action = SnapshotSyncPlan.action(
            localDirty: false,
            knownRevision: 12,
            remoteRevision: 12,
            remoteDataEqualsLocal: true
        )

        XCTAssertEqual(action, .noop)
    }

    func testMatchingRevisionsWithLocalChangesPush() {
        let action = SnapshotSyncPlan.action(
            localDirty: true,
            knownRevision: 12,
            remoteRevision: 12,
            remoteDataEqualsLocal: false
        )

        XCTAssertEqual(action, .pushLocal)
    }

    func testRemoteAheadWithCleanLocalAppliesRemote() {
        let action = SnapshotSyncPlan.action(
            localDirty: false,
            knownRevision: 12,
            remoteRevision: 15,
            remoteDataEqualsLocal: false
        )

        XCTAssertEqual(action, .applyRemote)
    }

    func testRemoteAheadWithIdenticalDataAdoptsRevisionWithoutWrite() {
        let action = SnapshotSyncPlan.action(
            localDirty: true,
            knownRevision: 12,
            remoteRevision: 15,
            remoteDataEqualsLocal: true
        )

        XCTAssertEqual(action, .adoptRevision)
    }

    func testDivergedSidesRequireManualConflictResolution() {
        let action = SnapshotSyncPlan.action(
            localDirty: true,
            knownRevision: 12,
            remoteRevision: 15,
            remoteDataEqualsLocal: false
        )

        XCTAssertEqual(action, .conflict)
    }
}
