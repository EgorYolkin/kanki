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

    func testSnapshotEncodesVersionDeckAndRenames() throws {
        let snapshot = LearningSnapshot(
            cards: [SessionCard(question: "Вопрос", answer: "Ответ", deck: "Математика")],
            deckRenames: [DeckRename(from: "Старое", to: "Математика")]
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        let cards = try XCTUnwrap(object["cards"] as? [[String: Any]])
        let renames = try XCTUnwrap(object["deck_renames"] as? [[String: String]])

        XCTAssertEqual(object["snapshot_version"] as? Int, 3)
        XCTAssertEqual(renames, [["from": "Старое", "to": "Математика"]])
        XCTAssertEqual(cards.first?["deck"] as? String, "Математика")
    }

    func testLegacyV1SnapshotDecodesWithDeckDefaults() throws {
        let data = Data(
            """
            {"cards":[{"id":"2621F15A-306C-435A-9680-AEEB602F272D",
            "question":"annals","answer":"bsbs","createdAt":730000}]}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(LearningSnapshot.self, from: data)

        XCTAssertEqual(decoded.snapshotVersion, LearningSnapshot.currentSnapshotVersion)
        XCTAssertTrue(decoded.deckRenames.isEmpty)
        XCTAssertEqual(decoded.cards.map(\.deck), [nil])
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

    func testArchivingKeepsHistoryAndCanBeUndone() {
        let review = SessionReview(cardID: card.id, rating: .good, reviewedAt: Date(timeIntervalSince1970: 300))
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
            cards: [card],
            reviews: [review],
            schedules: [card.id: schedule]
        )

        XCTAssertTrue(snapshot.setArchived(true, cardID: card.id))
        XCTAssertEqual(snapshot.cards.first?.isArchived, true)
        XCTAssertEqual(snapshot.reviews, [review])
        XCTAssertEqual(snapshot.schedules[card.id], schedule)

        XCTAssertTrue(snapshot.setArchived(false, cardID: card.id))
        XCTAssertEqual(snapshot.cards.first?.isArchived, false)

        XCTAssertFalse(snapshot.setArchived(true, cardID: UUID()))
    }

    func testArchivedCardSurvivesSnapshotRoundTrip() throws {
        let archived = SessionCard(question: "Вопрос", answer: "Ответ", isArchived: true)
        let snapshot = LearningSnapshot(cards: [archived])

        let decoded = try JSONDecoder().decode(
            LearningSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.cards, [archived])
        XCTAssertEqual(decoded.snapshotVersion, 3)
    }

    func testUpdatingCardKeepsIdentityAndRejectsEmptyInput() {
        var snapshot = LearningSnapshot(cards: [card])

        XCTAssertTrue(
            snapshot.updateCard(
                id: card.id,
                question: "  Новый вопрос  ",
                answer: "Новый ответ ",
                deck: " Физика "
            )
        )
        let updated = snapshot.cards[0]
        XCTAssertEqual(updated.id, card.id)
        XCTAssertEqual(updated.createdAt, card.createdAt)
        XCTAssertEqual(updated.question, "Новый вопрос")
        XCTAssertEqual(updated.answer, "Новый ответ")
        XCTAssertEqual(updated.deck, "Физика")

        XCTAssertFalse(snapshot.updateCard(id: card.id, question: " ", answer: "Ответ", deck: nil))
        XCTAssertEqual(snapshot.cards[0].question, "Новый вопрос")

        XCTAssertFalse(snapshot.updateCard(id: UUID(), question: "Вопрос", answer: "Ответ", deck: nil))
    }

}
