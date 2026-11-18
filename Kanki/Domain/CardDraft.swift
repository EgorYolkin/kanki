import Foundation

/// Проверяет заполненность полей, сохраняя исходный Markdown без изменений.
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

    private var hasQuestion: Bool {
        question.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    }

    private var hasAnswer: Bool {
        answer.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    }

    var isBlank: Bool {
        !hasQuestion && !hasAnswer
    }

    /// Кнопка сохранения активна только когда заполнены оба поля.
    var canSubmit: Bool {
        hasQuestion && hasAnswer
    }

    /// Готовая карточка или `nil`, если ввод не прошёл проверку.
    func makeCard() -> SessionCard? {
        guard canSubmit else { return nil }
        return SessionCard(question: question, answer: answer, deck: deck)
    }

    /// Карточка с обновлёнными текстом и категорией; `nil` — ввод пустой.
    /// Идентификатор, дата создания, архив и история повторений сохраняются.
    func updated(_ card: SessionCard) -> SessionCard? {
        guard canSubmit else { return nil }
        return SessionCard(
            id: card.id,
            question: question,
            answer: answer,
            createdAt: card.createdAt,
            deck: deck,
            isArchived: card.isArchived
        )
    }
}
