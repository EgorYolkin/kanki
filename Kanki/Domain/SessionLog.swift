import Foundation

/// Журнал оценок: счётчик и последняя оценка для списка карточек.
/// Читает сохранённые записи снимка; оценка добавляется через `CardScheduling`.
struct SessionLog: Equatable {
    private(set) var reviews: [SessionReview]

    init(reviews: [SessionReview] = []) {
        self.reviews = reviews
    }

    var count: Int { reviews.count }

    var lastRating: RecallRating? { reviews.last?.rating }

    func history(for cardID: UUID) -> [SessionReview] {
        reviews.reversed().filter { $0.cardID == cardID }
    }
}
