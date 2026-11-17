import Foundation
import FSRS

enum CardReviewError: LocalizedError {
    case staleCard

    var errorDescription: String? {
        "Карточка изменилась или больше недоступна для повторения. Откройте новый сеанс."
    }
}

/// Пересчитывает срок следующего показа по оценке ответа.
/// Чистая функция: дата и прежнее состояние передаются снаружи.
enum CardScheduling {
    /// Оценка относится к показанному содержимому, а не только к идентификатору.
    /// Проверка и расчёт завершаются до изменения снимка.
    static func record(
        _ card: SessionCard,
        rating: RecallRating,
        in snapshot: inout LearningSnapshot,
        at date: Date
    ) throws {
        guard !card.isArchived, snapshot.cards.contains(card) else {
            throw CardReviewError.staleCard
        }
        let schedule = try nextReview(for: snapshot.schedules[card.id], rating: rating, at: date)
        snapshot.reviews.append(SessionReview(cardID: card.id, rating: rating, reviewedAt: date))
        snapshot.schedules[card.id] = schedule
    }

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
