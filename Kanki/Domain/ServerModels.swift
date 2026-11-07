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

extension ServerSnapshot {
    /// Снимок неизвестной будущей схемы отклоняется: декодировать его
    /// дефолтами — значит молча применять непонятые данные.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int.self, forKey: .revision)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version <= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "schema_version \(version) новее поддерживаемой 1"
            )
        }
        schemaVersion = version
        data = try container.decodeIfPresent(LearningSnapshot.self, forKey: .data)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
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
