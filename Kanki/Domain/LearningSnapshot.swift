import Foundation

/// Локальный снимок демо-данных: карточки, их оценки и расписание FSRS.
/// Кодируется в JSON `LocalCardStore`; серверного источника пока нет.
struct LearningSnapshot: Codable, Equatable {
    var cards: [SessionCard]
    var reviews: [SessionReview]
    var schedules: [UUID: CardSchedule]

    init(
        cards: [SessionCard] = [],
        reviews: [SessionReview] = [],
        schedules: [UUID: CardSchedule] = [:]
    ) {
        self.cards = cards
        self.reviews = reviews
        self.schedules = schedules
    }

    private enum CodingKeys: String, CodingKey {
        case cards
        case reviews
        case schedules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
        try container.encode(cards, forKey: .cards)
        try container.encode(reviews, forKey: .reviews)
        let stored = Dictionary(uniqueKeysWithValues: schedules.map { ($0.key.uuidString, $0.value) })
        try container.encode(stored, forKey: .schedules)
    }
}
