import Foundation

/// Журнал оценок текущего сеанса: счётчик и последняя оценка для списка карточек.
struct SessionLog: Equatable {
    private(set) var reviews: [SessionReview] = []

    var count: Int { reviews.count }

    var lastRating: RecallRating? { reviews.last?.rating }

    mutating func record(_ card: SessionCard, rating: RecallRating, at date: Date = Date()) {
        reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: date))
    }
}
