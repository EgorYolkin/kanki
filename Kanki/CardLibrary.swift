import Foundation
import Observation

struct SessionCard: Codable, Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String

    init(id: UUID = UUID(), question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

enum RecallRating: Int, CaseIterable, Codable {
    case again = 1
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: "Снова"
        case .hard: "Трудно"
        case .good: "Хорошо"
        case .easy: "Легко"
        }
    }
}

struct SessionReview: Codable, Identifiable, Equatable {
    let id: UUID
    let cardID: UUID
    let rating: RecallRating
    let reviewedAt: Date

    init(id: UUID = UUID(), cardID: UUID, rating: RecallRating, reviewedAt: Date = Date()) {
        self.id = id
        self.cardID = cardID
        self.rating = rating
        self.reviewedAt = reviewedAt
    }
}

/// Локальный формат карточек; не Anki `.apkg` и не обменный контракт заметок.
struct CardArchive: Codable, Equatable {
    let formatVersion: Int
    let cards: [SessionCard]
    let reviews: [SessionReview]

    init(cards: [SessionCard], reviews: [SessionReview]) {
        formatVersion = 1
        self.cards = cards
        self.reviews = reviews
    }

    static func decode(_ data: Data) throws -> CardArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(CardArchive.self, from: data)
        let cardIDs = Set(archive.cards.map(\.id))
        guard archive.formatVersion == 1,
              cardIDs.count == archive.cards.count,
              Set(archive.reviews.map(\.id)).count == archive.reviews.count,
              archive.reviews.allSatisfy({ cardIDs.contains($0.cardID) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return archive
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

@MainActor @Observable
final class CardLibrary {
    private(set) var cards: [SessionCard] = []
    private(set) var reviews: [SessionReview] = []
    private(set) var loadError: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        reload()
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if let identifier = ProcessInfo.processInfo.environment["KANKI_CARD_LIBRARY_TEST_ID"],
           UUID(uuidString: identifier) != nil {
            return directory.appendingPathComponent("cards-\(identifier).json")
        }
        #endif
        return directory.appendingPathComponent("cards.json")
    }

    func reload() {
        do {
            let archive = FileManager.default.fileExists(atPath: fileURL.path)
                ? try CardArchive.decode(Data(contentsOf: fileURL))
                : CardArchive(cards: [], reviews: [])
            cards = archive.cards
            reviews = archive.reviews
            loadError = nil
        } catch {
            // Never replace an unreadable collection with an empty one.
            loadError = error.localizedDescription
        }
    }

    func add(question: String, answer: String) throws {
        try requireLoaded()
        cards.append(SessionCard(question: question, answer: answer))
        do {
            try persist()
        } catch {
            cards.removeLast()
            throw error
        }
    }

    func record(_ card: SessionCard, rating: RecallRating, at date: Date = Date()) throws {
        try requireLoaded()
        guard cards.contains(where: { $0.id == card.id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: date))
        do {
            try persist()
        } catch {
            reviews.removeLast()
            throw error
        }
    }

    func history(for cardID: UUID) -> [SessionReview] {
        reviews.reversed().filter { $0.cardID == cardID }
    }

    func export(selectedIDs: Set<UUID>? = nil) -> CardArchive {
        let exportedCards = selectedIDs.map { ids in cards.filter { ids.contains($0.id) } } ?? cards
        let exportedIDs = Set(exportedCards.map(\.id))
        return CardArchive(cards: exportedCards, reviews: reviews.filter { exportedIDs.contains($0.cardID) })
    }

    private func requireLoaded() throws {
        if loadError != nil {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func persist() throws {
        let data = try CardArchive(cards: cards, reviews: reviews).encoded()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
