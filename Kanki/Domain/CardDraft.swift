import Foundation

/// Ввод карточки: обрезает пробелы и не даёт сохранить пустые поля.
/// Используется и при создании, и при редактировании.
struct CardDraft: Equatable {
    var question = ""
    var answer = ""
    var deck: String?

    /// Заполнение формы текущими значениями карточки.
    init(question: String = "", answer: String = "", deck: String? = nil) {
        self.question = question
        self.answer = answer
        self.deck = deck
    }

    init(card: SessionCard) {
        question = card.question
        answer = card.answer
        deck = card.deck
    }

    var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAnswer: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Кнопка сохранения активна только когда заполнены оба поля.
    var canSubmit: Bool {
        !trimmedQuestion.isEmpty && !trimmedAnswer.isEmpty
    }

    /// Готовая карточка или `nil`, если ввод не прошёл проверку.
    func makeCard() -> SessionCard? {
        guard canSubmit else { return nil }
        return SessionCard(question: trimmedQuestion, answer: trimmedAnswer, deck: deck)
    }

    /// Карточка с обновлёнными текстом и категорией; `nil` — ввод пустой.
    /// Идентификатор, дата создания, архив и история повторений сохраняются.
    func updated(_ card: SessionCard) -> SessionCard? {
        guard canSubmit else { return nil }
        return SessionCard(
            id: card.id,
            question: trimmedQuestion,
            answer: trimmedAnswer,
            createdAt: card.createdAt,
            deck: deck,
            isArchived: card.isArchived
        )
    }
}
