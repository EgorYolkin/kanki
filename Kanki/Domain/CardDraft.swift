import Foundation

/// Ввод новой карточки: обрезает пробелы и не даёт создать пустую карточку.
struct CardDraft: Equatable {
    var question = ""
    var answer = ""

    var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAnswer: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Кнопка «Добавить» активна только когда заполнены оба поля.
    var canSubmit: Bool {
        !trimmedQuestion.isEmpty && !trimmedAnswer.isEmpty
    }

    /// Готовая карточка или `nil`, если ввод не прошёл проверку.
    func makeCard() -> SessionCard? {
        guard canSubmit else { return nil }
        return SessionCard(question: trimmedQuestion, answer: trimmedAnswer)
    }
}
