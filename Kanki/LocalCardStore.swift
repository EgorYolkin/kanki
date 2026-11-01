import Foundation

struct SessionCard: Identifiable, Codable, Equatable {
    let id: UUID
    let question: String
    let answer: String
    let createdAt: Date

    init(id: UUID = UUID(), question: String, answer: String, createdAt: Date = Date()) {
        self.id = id
        self.question = question
        self.answer = answer
        self.createdAt = createdAt
    }
}

enum RecallRating: Int, Codable, CaseIterable {
    case again = 1
    case hard
    case good
    case easy
}

struct SessionReview: Codable, Equatable {
    let cardID: UUID
    let rating: RecallRating
    let reviewedAt: Date
}

struct LearningSnapshot: Codable, Equatable {
    var cards: [SessionCard] = []
    var reviews: [SessionReview] = []
}

/// Local store used while no server is configured.
///
/// A JSON snapshot in Application Support is the source of truth on device; it is small,
/// human-inspectable and can be uploaded once sync exists. Every write replaces the file atomically.
enum LocalCardStore {
    /// Launch argument for UI tests: removes the snapshot before the first screen reads it.
    static let resetArgument = "--reset-store"

    private static let folderName = "Kanki"
    private static let fileName = "cards.json"

    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func load() throws -> LearningSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LearningSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LearningSnapshot.self, from: Data(contentsOf: fileURL))
    }

    static func save(_ snapshot: LearningSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
