import XCTest
@testable import Kanki

final class ServerModelsTests: XCTestCase {
    func testDecodesEmptySnapshot() throws {
        let data = Data(
            #"{"revision":0,"schema_version":1,"data":null,"updated_at":null}"#.utf8
        )

        let snapshot = try JSONDecoder().decode(ServerSnapshot.self, from: data)

        XCTAssertEqual(
            snapshot,
            ServerSnapshot(revision: 0, schemaVersion: 1, data: nil, updatedAt: nil)
        )
    }

    func testDecodesSnapshotWithLearningData() throws {
        let data = Data(
            """
            {"revision":3,"schema_version":1,"updated_at":"2026-01-01T00:00:00Z",
             "data":{"cards":[],"reviews":[]}}
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(ServerSnapshot.self, from: data)

        XCTAssertEqual(snapshot.revision, 3)
        XCTAssertEqual(snapshot.data, LearningSnapshot())
    }

    func testEncodesWriteEnvelope() throws {
        let write = ServerSnapshotWrite(snapshot: LearningSnapshot(), baseRevision: 4)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(write)) as? [String: Any]
        )

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["base_revision"] as? Int, 4)
        XCTAssertNotNil(object["data"])
    }

    func testIdentityDecodes() throws {
        let data = Data(#"{"label":"agent","role":"device"}"#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(ServerIdentity.self, from: data),
            ServerIdentity(label: "agent", role: "device")
        )
    }
}
