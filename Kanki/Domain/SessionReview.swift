import Foundation

/// Запись об оценке карточки. Хранится локально в JSON-снимке `LocalCardStore`.
struct SessionReview: Equatable, Codable {
    let cardID: UUID
    let rating: RecallRating
    let reviewedAt: Date
}
