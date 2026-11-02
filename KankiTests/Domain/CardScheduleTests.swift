import FSRS
import XCTest
@testable import Kanki

final class CardScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testMapsEveryCardStateBothWays() {
        let pairs: [(CardState, CardSchedule.State)] = [
            (.new, .new),
            (.learning, .learning),
            (.review, .review),
            (.relearning, .relearning)
        ]

        for (fsrsState, scheduleState) in pairs {
            let card = makeCard(state: fsrsState)
            let schedule = CardSchedule(card)

            XCTAssertEqual(schedule.state, scheduleState)
            XCTAssertEqual(schedule.fsrsCard, card)
        }
    }

    func testKeepsEveryField() {
        let lastReview = now.addingTimeInterval(-3_600)
        let card = Card(
            due: now,
            stability: 4.5,
            difficulty: 6.25,
            elapsedDays: 0.5,
            scheduledDays: 4,
            learningSteps: 2,
            reps: 7,
            lapses: 3,
            state: .relearning,
            lastReview: lastReview
        )

        let schedule = CardSchedule(card)

        XCTAssertEqual(schedule.due, now)
        XCTAssertEqual(schedule.stability, 4.5)
        XCTAssertEqual(schedule.difficulty, 6.25)
        XCTAssertEqual(schedule.elapsedDays, 0.5)
        XCTAssertEqual(schedule.scheduledDays, 4)
        XCTAssertEqual(schedule.learningSteps, 2)
        XCTAssertEqual(schedule.reps, 7)
        XCTAssertEqual(schedule.lapses, 3)
        XCTAssertEqual(schedule.state, .relearning)
        XCTAssertEqual(schedule.lastReview, lastReview)
    }

    func testNewCardIgnoresDueDateUntilRated() {
        var schedule = CardSchedule(makeCard(state: .new))
        schedule.due = now.addingTimeInterval(86_400)

        XCTAssertEqual(schedule.status(at: now), .new)
    }

    func testDueAndScheduledStatus() {
        var schedule = CardSchedule(makeCard(state: .review))

        schedule.due = now
        XCTAssertEqual(schedule.status(at: now), .due)

        schedule.due = now.addingTimeInterval(-1)
        XCTAssertEqual(schedule.status(at: now), .due)

        schedule.due = now.addingTimeInterval(60)
        XCTAssertEqual(schedule.status(at: now), .scheduled(now.addingTimeInterval(60)))
    }

    private func makeCard(state: CardState) -> Card {
        Card(
            due: now,
            stability: 1.5,
            difficulty: 5.5,
            elapsedDays: 1,
            scheduledDays: 2,
            learningSteps: 0,
            reps: 1,
            lapses: 0,
            state: state,
            lastReview: state == .new ? nil : now
        )
    }
}
