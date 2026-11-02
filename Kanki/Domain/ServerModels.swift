import Foundation

struct ServerIdentity: Codable, Equatable {
    let label: String
    let role: String
}

/// Снимок с сервера. `data == nil` означает, что на сервере ещё нет данных.
struct ServerSnapshot: Codable, Equatable {
    let revision: Int
    let schemaVersion: Int
    let data: LearningSnapshot?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case revision
        case schemaVersion = "schema_version"
        case data
        case updatedAt = "updated_at"
    }
}

struct ServerSnapshotWrite: Encodable, Equatable {
    let schemaVersion: Int
    let baseRevision: Int
    let data: LearningSnapshot

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case baseRevision = "base_revision"
        case data
    }

    init(snapshot: LearningSnapshot, baseRevision: Int) {
        self.schemaVersion = 1
        self.baseRevision = baseRevision
        self.data = snapshot
    }
}

enum ServerError: Error, Equatable {
    case invalidResponse
    case unauthorized
    case conflict(currentRevision: Int)
    case http(status: Int)
    case decoding
}
