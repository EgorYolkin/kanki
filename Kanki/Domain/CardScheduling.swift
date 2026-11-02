import Foundation
import FSRS

/// Пересчитывает срок следующего показа по оценке ответа.
/// Чистая функция: дата и прежнее состояние передаются снаружи.
enum CardScheduling {
    static func nextReview(
        for schedule: CardSchedule?,
        rating: RecallRating,
        at date: Date = Date()
    ) throws -> CardSchedule {
        let card = schedule?.fsrsCard ?? Card(due: date)
        let grade: Rating = switch rating {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
        let next = try FSRS(parameters: .init()).next(card: card, now: date, grade: grade)
        return CardSchedule(next.card)
    }
}
