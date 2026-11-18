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

    func testRemoteSnapshotWithDuplicateCardIDsIsRejected() throws {
        let payload = try JSONEncoder().encode(LearningSnapshot(cards: [card, card]))

        XCTAssertThrowsError(try JSONDecoder().decode(LearningSnapshot.self, from: payload)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected a catchable data-corruption error, got \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["cards"])
        }
    }

    func testScheduleKeysDifferingOnlyByUUIDCaseAreRejected() {
        let schedule = """
        {"due":0,"stability":0,"difficulty":0,"elapsedDays":0,
        "scheduledDays":0,"learningSteps":0,"reps":0,"lapses":0,"state":"new"}
        """
        let payload = Data(
            """
            {"schedules":{
            "2621F15A-306C-435A-9680-AEEB602F272D":\(schedule),
            "2621f15a-306c-435a-9680-aeeb602f272d":\(schedule)}}
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(LearningSnapshot.self, from: payload)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected a catchable data-corruption error, got \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["schedules"])
        }
    }

    func testSupportedVersionsKeepLegacyDefaultsAndOrphanReviews() throws {
        for version in 1...3 {
            let payload = Data(
                """
                {"snapshot_version":\(version),
                "cards":[{"id":"2621F15A-306C-435A-9680-AEEB602F272D",
                "question":"Вопрос","answer":"Ответ","createdAt":100}],
                "reviews":[{"cardID":"11111111-1111-1111-1111-111111111111",
                "rating":3,"reviewedAt":200}]}
                """.utf8
            )

            let decoded = try JSONDecoder().decode(LearningSnapshot.self, from: payload)

            XCTAssertEqual(decoded.snapshotVersion, version)
            XCTAssertEqual(decoded.cards.count, 1)
            XCTAssertNil(decoded.cards.first?.deck)
            XCTAssertEqual(decoded.cards.first?.isArchived, false)
            XCTAssertEqual(decoded.reviews.count, 1)
            XCTAssertNotEqual(decoded.reviews.first?.cardID, decoded.cards.first?.id)
            XCTAssertTrue(decoded.schedules.isEmpty)
            XCTAssertTrue(decoded.deckRenames.isEmpty)
        }
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

    func testRemovingUncategorizedCardsKeepsNamedHierarchyAndUnrelatedRecords() {
        let active = removalCard(1)
        let archived = removalCard(2, isArchived: true)
        let named = removalCard(3, deck: "Наука")
        let child = removalCard(4, deck: "Наука::Физика", isArchived: true)
        let orphanID = removalCard(5).id
        let date = Date(timeIntervalSince1970: 300)
        let activeReview = SessionReview(cardID: active.id, rating: .good, reviewedAt: date)
        let archivedReview = SessionReview(cardID: archived.id, rating: .hard, reviewedAt: date)
        let namedReview = SessionReview(cardID: named.id, rating: .easy, reviewedAt: date)
        let childReview = SessionReview(cardID: child.id, rating: .good, reviewedAt: date)
        let orphanReview = SessionReview(cardID: orphanID, rating: .again, reviewedAt: date)
        let schedule = removalSchedule
        let renames = [DeckRename(from: "Старое", to: "Наука")]
        var snapshot = LearningSnapshot(
            cards: [named, active, child, archived],
            reviews: [activeReview, orphanReview, childReview, archivedReview, namedReview, activeReview],
            schedules: [
                active.id: schedule, archived.id: schedule, named.id: schedule,
                child.id: schedule, orphanID: schedule
            ],
            deckRenames: renames
        )
        snapshot.snapshotVersion = 2

        XCTAssertEqual(snapshot.uncategorizedCardCount, 2)
        XCTAssertEqual(snapshot.removeUncategorizedCards(), 2)

        XCTAssertEqual(snapshot.cards, [named, child])
        XCTAssertEqual(snapshot.reviews, [orphanReview, childReview, namedReview])
        XCTAssertEqual(snapshot.schedules, [named.id: schedule, child.id: schedule, orphanID: schedule])
        XCTAssertEqual(snapshot.deckRenames, renames)
        XCTAssertEqual(snapshot.snapshotVersion, 2)
        XCTAssertEqual(snapshot.uncategorizedCardCount, 0)
        let remaining = snapshot
        XCTAssertEqual(snapshot.removeUncategorizedCards(), 0)
        XCTAssertEqual(snapshot, remaining)
    }

    func testRemovingUncategorizedCardsIncludesArchivedOnlyGroup() {
        let archived = removalCard(1, isArchived: true)
        var snapshot = LearningSnapshot(
            cards: [archived],
            reviews: [
                SessionReview(cardID: archived.id, rating: .good, reviewedAt: Date(timeIntervalSince1970: 300))
            ],
            schedules: [archived.id: removalSchedule]
        )

        XCTAssertEqual(snapshot.uncategorizedCardCount, 1)
        XCTAssertEqual(snapshot.removeUncategorizedCards(), 1)

        XCTAssertEqual(snapshot, LearningSnapshot())
        XCTAssertEqual(snapshot.uncategorizedCardCount, 0)
    }

    func testRemovingUncategorizedCardsWithoutNilDeckLeavesSnapshotUnchanged() {
        let named = removalCard(1, deck: "Наука")
        let orphanID = removalCard(2).id
        let original = LearningSnapshot(
            cards: [named],
            reviews: [
                SessionReview(cardID: orphanID, rating: .hard, reviewedAt: Date(timeIntervalSince1970: 300))
            ],
            schedules: [named.id: removalSchedule, orphanID: removalSchedule],
            deckRenames: [DeckRename(from: "Старое", to: "Наука")]
        )
        var snapshot = original

        XCTAssertEqual(snapshot.uncategorizedCardCount, 0)
        XCTAssertEqual(snapshot.removeUncategorizedCards(), 0)
        XCTAssertEqual(snapshot, original)

        var empty = LearningSnapshot()
        XCTAssertEqual(empty.removeUncategorizedCards(), 0)
        XCTAssertEqual(empty, LearningSnapshot())
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

    func testFutureSnapshotVersionIsRejected() {
        let data = Data(#"{"snapshot_version":4,"cards":[],"reviews":[]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(LearningSnapshot.self, from: data))
    }
}

extension LearningSnapshotTests {
    private func removalCard(
        _ id: UInt8,
        deck: String? = nil,
        isArchived: Bool = false
    ) -> SessionCard {
        SessionCard(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            question: "Демо-вопрос \(id)",
            answer: "Демо-ответ",
            createdAt: Date(timeIntervalSince1970: 100),
            deck: deck,
            isArchived: isArchived
        )
    }

    private var removalSchedule: CardSchedule {
        CardSchedule(
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
    }
}
