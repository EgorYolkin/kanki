import Foundation

/// Локальный снимок демо-данных: карточки, их оценки и расписание FSRS.
/// Кодируется в JSON `LocalCardStore`; серверного источника пока нет.
struct LearningSnapshot: Codable, Equatable {
    /// Версия состава payload: 2 — добавлены категории (`deck`) и `deck_renames`.
    /// Отсутствие ключа при декодировании — старый снимок v1, принимается без потерь.
    static let currentSnapshotVersion = 2

    var snapshotVersion: Int
    var cards: [SessionCard]
    var reviews: [SessionReview]
    var schedules: [UUID: CardSchedule]
    var deckRenames: [DeckRename]

    init(
        cards: [SessionCard] = [],
        reviews: [SessionReview] = [],
        schedules: [UUID: CardSchedule] = [:],
        deckRenames: [DeckRename] = []
    ) {
        self.snapshotVersion = Self.currentSnapshotVersion
        self.cards = cards
        self.reviews = reviews
        self.schedules = schedules
        self.deckRenames = deckRenames
    }

    /// Локальные категории с числом карточек — для обнаружения потерь при загрузке.
    var localDeckCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for card in cards {
            guard let deck = card.deck else { continue }
            counts[deck, default: 0] += 1
        }
        return counts
    }

    @discardableResult
    mutating func removeCard(id: UUID) -> Bool {
        guard cards.contains(where: { $0.id == id }) else { return false }
        cards.removeAll { $0.id == id }
        reviews.removeAll { $0.cardID == id }
        schedules.removeValue(forKey: id)
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotVersion = "snapshot_version"
        case cards
        case reviews
        case schedules
        case deckRenames = "deck_renames"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Снапшот v1 (без версий и категорий) декодируется как v2 с дефолтами.
        snapshotVersion = try container.decodeIfPresent(Int.self, forKey: .snapshotVersion)
            ?? Self.currentSnapshotVersion
        deckRenames = try container.decodeIfPresent([DeckRename].self, forKey: .deckRenames) ?? []
        cards = try container.decodeIfPresent([SessionCard].self, forKey: .cards) ?? []
        reviews = try container.decodeIfPresent([SessionReview].self, forKey: .reviews) ?? []
        let stored = try container.decodeIfPresent([String: CardSchedule].self, forKey: .schedules) ?? [:]
        schedules = try Dictionary(uniqueKeysWithValues: stored.map { key, schedule in
            guard let id = UUID(uuidString: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schedules,
                    in: container,
                    debugDescription: "Некорректный идентификатор карточки: \(key)"
                )
            }
            return (id, schedule)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snapshotVersion, forKey: .snapshotVersion)
        try container.encode(cards, forKey: .cards)
        try container.encode(reviews, forKey: .reviews)
        try container.encode(deckRenames, forKey: .deckRenames)
        let stored = Dictionary(uniqueKeysWithValues: schedules.map { ($0.key.uuidString, $0.value) })
        try container.encode(stored, forKey: .schedules)
    }
}
