import Foundation

/// Журнал оценок: счётчик и последняя оценка для списка карточек.
/// Инициализируется сохранёнными записями и пополняется в сеансе.
struct SessionLog: Equatable {
    private(set) var reviews: [SessionReview]

    init(reviews: [SessionReview] = []) {
        self.reviews = reviews
    }

    var count: Int { reviews.count }

    var lastRating: RecallRating? { reviews.last?.rating }

    mutating func record(_ card: SessionCard, rating: RecallRating, at date: Date = Date()) {
        reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: date))
    }

    func history(for cardID: UUID) -> [SessionReview] {
        reviews.reversed().filter { $0.cardID == cardID }
    }

    /// Откат записи только после неудачного сохранения на диск.
    mutating func discardLastRecord() {
        reviews.removeLast()
    }
}
