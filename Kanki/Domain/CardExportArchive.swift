import Foundation

/// Отдельный формат выгрузки локальных карточек; не пакет Anki или контракт заметок.
struct CardExportArchive: Codable, Equatable {
    let formatVersion: Int
    let cards: [SessionCard]
    let reviews: [SessionReview]

    init(snapshot: LearningSnapshot, selectedIDs: Set<UUID>? = nil) {
        formatVersion = 1
        cards = selectedIDs.map { ids in snapshot.cards.filter { ids.contains($0.id) } } ?? snapshot.cards
        let exportedIDs = Set(cards.map(\.id))
        reviews = snapshot.reviews.filter { exportedIDs.contains($0.cardID) }
    }

    static func decode(_ data: Data) throws -> CardExportArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(CardExportArchive.self, from: data)
        let cardIDs = Set(archive.cards.map(\.id))
        guard archive.formatVersion == 1,
              cardIDs.count == archive.cards.count,
              archive.reviews.allSatisfy({ cardIDs.contains($0.cardID) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return archive
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
