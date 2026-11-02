import Foundation
import FSRS

/// Сохранённое состояние FSRS для одной карточки.
/// Кодируется в JSON-снимок `LocalCardStore` рядом с карточкой.
struct CardSchedule: Equatable, Codable {
    enum State: String, Codable {
        case new
        case learning
        case review
        case relearning
    }

    var due: Date
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var scheduledDays: Double
    var learningSteps: Int
    var reps: Int
    var lapses: Int
    var state: State
    var lastReview: Date?
}

/// Положение карточки относительно текущего момента.
enum CardReviewStatus: Equatable {
    case new
    case due
    case scheduled(Date)
}

extension CardSchedule {
    func status(at date: Date) -> CardReviewStatus {
        if state == .new {
            return .new
        }
        if due <= date {
            return .due
        }
        return .scheduled(due)
    }

    init(_ card: Card) {
        due = card.due
        stability = card.stability
        difficulty = card.difficulty
        elapsedDays = card.elapsedDays
        scheduledDays = card.scheduledDays
        learningSteps = card.learningSteps
        reps = card.reps
        lapses = card.lapses
        state = switch card.state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
        lastReview = card.lastReview
    }

    var fsrsCard: Card {
        Card(
            due: due,
            stability: stability,
            difficulty: difficulty,
            elapsedDays: elapsedDays,
            scheduledDays: scheduledDays,
            learningSteps: learningSteps,
            reps: reps,
            lapses: lapses,
            state: fsrsState,
            lastReview: lastReview
        )
    }

    private var fsrsState: CardState {
        switch state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
    }
}
