import Foundation

/// Карточка демо-сеанса. Живёт только в памяти и исчезает при перезапуске.
struct SessionCard: Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String

    init(id: UUID = UUID(), question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}
