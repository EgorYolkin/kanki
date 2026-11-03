import Foundation

/// Локальный снимок демо-данных: карточки, их оценки и расписание FSRS.
/// Кодируется в JSON `LocalCardStore`; серверного источника пока нет.
struct LearningSnapshot: Codable, Equatable {
    /// Версия состава payload: 2 — категории (`deck`, `deck_renames`),
    /// 3 — архив карточки (`isArchived` в карточке).
    /// Отсутствие ключа при декодировании — старый снимок, принимается с дефолтами.
    static let currentSnapshotVersion = 3

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

    /// Архивирует или возвращает карточку; история и расписание сохраняются.
    @discardableResult
    mutating func setArchived(_ archived: Bool, cardID: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return false }
        cards[index].isArchived = archived
        return true
    }

    /// Правка текста и категории карточки: пустые поля отклоняются (`CardDraft`),
    /// идентификатор, дата создания, архив и история сохраняются.
    @discardableResult
    mutating func updateCard(id: UUID, question: String, answer: String, deck: String?) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return false }
        var draft = CardDraft(card: cards[index])
        draft.question = question
        draft.answer = answer
        draft.deck = deck
        guard let edited = draft.updated(cards[index]) else { return false }
        cards[index] = edited
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
        // Снимок без версии (v1) декодируется как текущий с дефолтами.
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
