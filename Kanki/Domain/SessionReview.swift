import Foundation

/// Запись об оценке карточки в текущем сеансе.
struct SessionReview: Equatable {
    let cardID: UUID
    let rating: RecallRating
    let reviewedAt: Date
}
