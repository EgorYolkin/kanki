import Foundation

/// Очередь повторения сеанса: одна карточка за раз, ответ скрыт до запроса,
/// после оценки очередь идёт дальше и в конце показывает итог.
struct ReviewSessionState {
    let cards: [SessionCard]
    private(set) var index = 0
    private(set) var counts: [RecallRating: Int] = [:]
    private(set) var isAnswerVisible = false

    init(cards: [SessionCard]) {
        self.cards = cards
    }

    var currentCard: SessionCard? {
        cards.indices.contains(index) ? cards[index] : nil
    }

    var isFinished: Bool { currentCard == nil }

    var progressText: String {
        "Карточка \(min(index + 1, cards.count)) из \(cards.count)"
    }

    var reviewedCount: Int {
        counts.values.reduce(0, +)
    }

    /// Оценки в порядке кнопок, без нулевых значений.
    var summaryRows: [(rating: RecallRating, count: Int)] {
        RecallRating.allCases.compactMap { rating in
            guard let count = counts[rating], count > 0 else { return nil }
            return (rating, count)
        }
    }

    mutating func revealAnswer() {
        isAnswerVisible = true
    }

    /// Записывает оценку текущей карточки и переходит к следующей.
    /// Возвращает запись для журнала или `nil`, если очередь уже пройдена.
    mutating func record(_ rating: RecallRating, at date: Date = Date()) -> SessionReview? {
        guard let card = currentCard else { return nil }
        counts[rating, default: 0] += 1
        isAnswerVisible = false
        index += 1
        return SessionReview(cardID: card.id, rating: rating, reviewedAt: date)
    }
}
