import Foundation

/// Карточка демо-обучения. Хранится локально в JSON-снимке `LocalCardStore`.
struct SessionCard: Identifiable, Equatable, Codable {
    let id: UUID
    let question: String
    let answer: String
    let createdAt: Date
    /// Имя категории (колоды Anki). `nil` или пустая строка — «Без категории».
    /// Иерархия — только в имени через `::`; отдельной сущности категории нет.
    var deck: String?

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        createdAt: Date = Date(),
        deck: String? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.createdAt = createdAt
        self.deck = CardCategory.trimmedDeck(deck)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case question
        case answer
        case createdAt
        case deck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        answer = try container.decode(String.self, forKey: .answer)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Снапшот v1 (без категорий) декодируется без потерь: нет `deck` → «Без категории».
        deck = CardCategory.trimmedDeck(
            try container.decodeIfPresent(String.self, forKey: .deck)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encode(answer, forKey: .answer)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deck, forKey: .deck)
    }
}
