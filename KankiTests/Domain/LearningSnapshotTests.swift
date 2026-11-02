import XCTest
@testable import Kanki

final class LearningSnapshotTests: XCTestCase {
    private let card = SessionCard(
        question: "Вопрос",
        answer: "Ответ",
        createdAt: Date(timeIntervalSince1970: 100)
    )

    func testRoundTripKeepsSchedules() throws {
        let schedule = CardSchedule(
            due: Date(timeIntervalSince1970: 500),
            stability: 4.5,
            difficulty: 6,
            elapsedDays: 2,
            scheduledDays: 4,
            learningSteps: 1,
            reps: 3,
            lapses: 1,
            state: .review,
            lastReview: Date(timeIntervalSince1970: 400)
        )
        let snapshot = LearningSnapshot(
            cards: [card],
            reviews: [SessionReview(cardID: card.id, rating: .good, reviewedAt: Date(timeIntervalSince1970: 300))],
            schedules: [card.id: schedule]
        )

        let decoded = try JSONDecoder().decode(
            LearningSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded, snapshot)
    }

    func testLegacySnapshotWithoutSchedulesDecodes() throws {
        let data = Data(#"{"cards":[],"reviews":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(LearningSnapshot.self, from: data)

        XCTAssertEqual(decoded, LearningSnapshot())
    }

    func testEmptyObjectDecodesToEmptySnapshot() throws {
        let decoded = try JSONDecoder().decode(LearningSnapshot.self, from: Data("{}".utf8))

        XCTAssertEqual(decoded, LearningSnapshot())
    }

    func testInvalidScheduleKeyFailsLoudly() {
        let data = Data(
            """
            {"schedules":{"not-a-uuid":{"due":0,"stability":0,"difficulty":0,"elapsedDays":0,
            "scheduledDays":0,"learningSteps":0,"reps":0,"lapses":0,"state":"new"}}}
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(LearningSnapshot.self, from: data))
    }

    func testRemovingCardAlsoRemovesItsHistoryAndScheduleWithoutChangingOtherCards() {
        let other = SessionCard(question: "Другой", answer: "Ответ")
        let review = SessionReview(cardID: card.id, rating: .good, reviewedAt: Date(timeIntervalSince1970: 300))
        let otherReview = SessionReview(cardID: other.id, rating: .easy, reviewedAt: Date(timeIntervalSince1970: 400))
        let orphanReview = SessionReview(cardID: UUID(), rating: .hard, reviewedAt: Date(timeIntervalSince1970: 200))
        let schedule = CardSchedule(
            due: Date(timeIntervalSince1970: 500),
            stability: 4.5,
            difficulty: 6,
            elapsedDays: 2,
            scheduledDays: 4,
            learningSteps: 1,
            reps: 3,
            lapses: 1,
            state: .review,
            lastReview: Date(timeIntervalSince1970: 400)
        )
        var snapshot = LearningSnapshot(
            cards: [card, other],
            reviews: [orphanReview, review, otherReview],
            schedules: [card.id: schedule, other.id: schedule]
        )

        XCTAssertTrue(snapshot.removeCard(id: card.id))
        XCTAssertEqual(snapshot.cards, [other])
        XCTAssertEqual(snapshot.reviews, [orphanReview, otherReview])
        XCTAssertEqual(snapshot.schedules, [other.id: schedule])
        XCTAssertFalse(snapshot.removeCard(id: card.id))
        XCTAssertEqual(snapshot.reviews, [orphanReview, otherReview])
    }

}
