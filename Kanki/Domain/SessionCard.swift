import Foundation

/// Карточка демо-обучения. Хранится локально в JSON-снимке `LocalCardStore`.
struct SessionCard: Identifiable, Equatable, Codable {
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
