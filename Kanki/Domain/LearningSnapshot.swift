import Foundation

/// Полный снимок ручных карточек, их расписания, истории и источников.
struct LearningSnapshot: Codable, Equatable {
    /// До первого урока сохраняем формат v3, который умеют читать прежние клиенты.
    static let legacySnapshotVersion = 3
    static let lessonSnapshotVersion = 4
    static let currentSnapshotVersion = lessonSnapshotVersion

    var snapshotVersion: Int
    var cards: [SessionCard]
    var reviews: [SessionReview]
    var schedules: [UUID: CardSchedule]
    var deckRenames: [DeckRename]
    var lessons: [Lesson]

    init(
        cards: [SessionCard] = [],
        reviews: [SessionReview] = [],
        schedules: [UUID: CardSchedule] = [:],
        deckRenames: [DeckRename] = [],
        lessons: [Lesson] = []
    ) {
        snapshotVersion = lessons.isEmpty ? Self.legacySnapshotVersion : Self.lessonSnapshotVersion
        self.cards = cards
        self.reviews = reviews
        self.schedules = schedules
        self.deckRenames = deckRenames
        self.lessons = lessons
    }

    enum ValidationError: Error {
        case duplicateCardID(UUID)
        case invalidVersion(Int)
        case lessonsInLegacySnapshot
    }

    /// Только для локальной мутации: pull/reload не меняют версию полученного снимка.
    mutating func prepareForLocalMutation() {
        if (1..<Self.legacySnapshotVersion).contains(snapshotVersion) {
            snapshotVersion = Self.legacySnapshotVersion
        }
    }

    func validate() throws {
        guard (1...Self.currentSnapshotVersion).contains(snapshotVersion) else { throw ValidationError.invalidVersion(snapshotVersion) }
        guard snapshotVersion >= Self.lessonSnapshotVersion || lessons.isEmpty else { throw ValidationError.lessonsInLegacySnapshot }
        var cardIDs = Set<UUID>(minimumCapacity: cards.count)
        for card in cards {
            guard cardIDs.insert(card.id).inserted else {
                throw ValidationError.duplicateCardID(card.id)
            }
        }
        try validateLessons(cardIDs: cardIDs)
    }

    @discardableResult
    mutating func removeCard(id: UUID) -> Bool {
        guard cards.contains(where: { $0.id == id }) else { return false }
        cards.removeAll { $0.id == id }
        reviews.removeAll { $0.cardID == id }
        schedules.removeValue(forKey: id)
        for index in lessons.indices {
            lessons[index].cardIDs.removeAll { $0 == id }
        }
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
        case lessons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .snapshotVersion)
            ?? Self.legacySnapshotVersion
        guard (1...Self.currentSnapshotVersion).contains(version) else {
            throw DecodingError.dataCorruptedError(
                forKey: .snapshotVersion,
                in: container,
                debugDescription: "Неподдерживаемая версия снимка: \(version)"
            )
        }
        snapshotVersion = version
        if version >= Self.lessonSnapshotVersion {
            lessons = try container.decode([Lesson].self, forKey: .lessons)
        } else {
            guard !container.contains(.lessons) else {
                throw DecodingError.dataCorruptedError(forKey: .lessons, in: container, debugDescription: "Уроки требуют снимка версии 4")
            }
            lessons = []
        }
        deckRenames = try container.decodeIfPresent([DeckRename].self, forKey: .deckRenames) ?? []
        cards = try container.decodeIfPresent([SessionCard].self, forKey: .cards) ?? []
        reviews = try container.decodeIfPresent([SessionReview].self, forKey: .reviews) ?? []
        let stored = try container.decodeIfPresent([String: CardSchedule].self, forKey: .schedules) ?? [:]
        schedules = Dictionary(minimumCapacity: stored.count)
        for (key, schedule) in stored {
            guard let id = UUID(uuidString: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schedules,
                    in: container,
                    debugDescription: "Некорректный идентификатор карточки: \(key)"
                )
            }
            guard schedules.updateValue(schedule, forKey: id) == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schedules,
                    in: container,
                    debugDescription: "Повторяющийся идентификатор расписания: \(key)"
                )
            }
        }
        do {
            try validate()
        } catch ValidationError.duplicateCardID {
            throw DecodingError.dataCorruptedError(
                forKey: .cards,
                in: container,
                debugDescription: "Повторяющийся идентификатор карточки"
            )
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .lessons, in: container, debugDescription: error.localizedDescription)
        }
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snapshotVersion, forKey: .snapshotVersion)
        if snapshotVersion >= Self.lessonSnapshotVersion {
            try container.encode(lessons, forKey: .lessons)
        }
        try container.encode(cards, forKey: .cards)
        try container.encode(reviews, forKey: .reviews)
        try container.encode(deckRenames, forKey: .deckRenames)
        let stored = Dictionary(uniqueKeysWithValues: schedules.map { ($0.key.uuidString, $0.value) })
        try container.encode(stored, forKey: .schedules)
    }
}
