import XCTest
@testable import Kanki

final class ReviewQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testKeepsNewAndDueCardsInStableOrder() {
        let newOld = card("new-old", createdAt: 100)
        let newNew = card("new-new", createdAt: 300)
        let dueSoon = card("due-soon", createdAt: 50)
        let dueLater = card("due-later", createdAt: 40)
        let future = card("future", createdAt: 10)

        let cards = [future, dueLater, newNew, newOld, dueSoon]
        let schedules = [
            dueSoon.id: schedule(due: 200),
            dueLater.id: schedule(due: 400),
            future.id: schedule(due: 1_000)
        ]

        let queue = ReviewQueue.cards(
            cards,
            schedules: schedules,
            at: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(queue.map(\.question), ["new-old", "due-soon", "new-new", "due-later"])
    }

    func testNewCardsUseCreatedAtWhenDatesMatch() {
        let first = card("first", createdAt: 100)
        let second = card("second", createdAt: 100)
        let expected = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }

        let queue = ReviewQueue.cards([second, first], schedules: [:], at: now)

        XCTAssertEqual(queue, expected)
    }

    func testEmptyQueue() {
        XCTAssertTrue(ReviewQueue.cards([], schedules: [:], at: now).isEmpty)
    }

    func testArchivedCardsNeverEnterTheQueue() {
        let active = card("active", createdAt: 100)
        let archivedDue = SessionCard(
            question: "archived",
            answer: "A",
            createdAt: Date(timeIntervalSince1970: 50),
            isArchived: true
        )
        let schedules = [archivedDue.id: schedule(due: 200)]

        let queue = ReviewQueue.cards(
            [archivedDue, active],
            schedules: schedules,
            at: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(queue.map(\.question), ["active"])
    }

    private func card(_ question: String, createdAt: TimeInterval) -> SessionCard {
        SessionCard(
            question: question,
            answer: "A",
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func schedule(due: TimeInterval) -> CardSchedule {
        CardSchedule(
            due: Date(timeIntervalSince1970: due),
            stability: 1,
            difficulty: 5,
            elapsedDays: 0,
            scheduledDays: 1,
            learningSteps: 0,
            reps: 1,
            lapses: 0,
            state: .review,
            lastReview: Date(timeIntervalSince1970: 0)
        )
    }
}
