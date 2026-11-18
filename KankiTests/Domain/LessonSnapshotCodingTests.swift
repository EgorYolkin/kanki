import XCTest
@testable import Kanki

final class LessonSnapshotCodingTests: XCTestCase {
    private let lessonID = "00000000-0000-0000-0000-000000000001"
    private let cardID = "00000000-0000-0000-0000-000000000002"
    private let otherID = "00000000-0000-0000-0000-000000000003"

    private var lesson: [String: Any] {
        ["id": lessonID, "title": "Введение", "course": "Swift", "source_url": "https://example.org/1", "createdAt": 100, "card_ids": [cardID]]
    }

    private var legacyData: [String: Any] {
        [
            "cards": [["id": cardID, "question": "Вопрос", "answer": "Ответ", "deck": "Тема", "createdAt": 100, "isArchived": true]],
            "reviews": [["cardID": cardID, "rating": 3, "reviewedAt": 120]],
            "schedules": [
                cardID: [
                    "due": 200, "stability": 3, "difficulty": 2, "elapsedDays": 1, "scheduledDays": 2,
                    "learningSteps": 1, "reps": 1, "lapses": 0, "state": "review", "lastReview": 120
                ]
            ],
            "deck_renames": [["from": "Топик", "to": "Тема"]]
        ]
    }

    private func decode(_ object: [String: Any]) throws -> LearningSnapshot {
        try JSONDecoder().decode(LearningSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func encode(_ snapshot: LearningSnapshot) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    }

    func testFirstLessonPromotesOnceWithoutChangingLegacyData() throws {
        let id = try XCTUnwrap(UUID(uuidString: lessonID))
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let link = try XCTUnwrap(URL(string: "https://example.org/1"))
        for version: Int? in [nil, 1, 2, 3] {
            var payload = legacyData
            if let version { payload["snapshot_version"] = version }
            var snapshot = try decode(payload)
            XCTAssertEqual(snapshot.snapshotVersion, version ?? 3)
            XCTAssertEqual(snapshot.lessons, [])
            XCTAssertNil(try encode(snapshot)["lessons"])
            let original = snapshot
            snapshot.prepareForLocalMutation()
            XCTAssertEqual(snapshot.snapshotVersion, 3)
            XCTAssertTrue(snapshot.updateCard(id: snapshot.cards[0].id, question: "Правка", answer: "Ответ", deck: "Тема"))
            XCTAssertNil(try encode(snapshot)["lessons"])
            XCTAssertTrue(snapshot.cards[0].isArchived)
            let editedCards = snapshot.cards
            try snapshot.createLesson(id: id, title: "Введение", course: "Swift", sourceURL: link, createdAt: date)
            snapshot.lessons[0].cardIDs.append(snapshot.cards[0].id)
            let wire = try encode(snapshot)
            XCTAssertEqual(wire["snapshot_version"] as? Int, 4)
            let storedLessons = try XCTUnwrap(wire["lessons"] as? [[String: Any]])
            let stored = try XCTUnwrap(storedLessons.first)
            XCTAssertEqual(stored["card_ids"] as? [String], [cardID])
            XCTAssertEqual(stored["source_url"] as? String, link.absoluteString)
            XCTAssertEqual(stored["createdAt"] as? Double, 100)
            let restored = try decode(wire)
            XCTAssertEqual(restored, snapshot)
            XCTAssertEqual(restored.cards, editedCards)
            XCTAssertEqual(restored.reviews, original.reviews)
            XCTAssertEqual(restored.schedules, original.schedules)
            XCTAssertEqual(restored.deckRenames, original.deckRenames)
            try snapshot.removeLesson(id: id)
            snapshot.prepareForLocalMutation()
            let emptied = try encode(snapshot)
            XCTAssertEqual(emptied["snapshot_version"] as? Int, 4)
            XCTAssertEqual((emptied["lessons"] as? [Any])?.count, 0)
            XCTAssertEqual(try decode(emptied), snapshot)
        }
    }

    func testV4RequiresArrayAndLegacyForbidsEvenEmptyOrNullLessons() throws {
        XCTAssertThrowsError(try decode(["snapshot_version": 4]))
        XCTAssertThrowsError(try decode(["snapshot_version": 4, "lessons": NSNull()]))
        XCTAssertThrowsError(try decode(["snapshot_version": 3, "lessons": []]))
        XCTAssertThrowsError(try decode(["snapshot_version": 2, "lessons": NSNull()]))
        XCTAssertThrowsError(try decode(["lessons": []]))
        let emptyV4 = try decode(["snapshot_version": 4, "lessons": []])
        XCTAssertNotEqual(emptyV4, LearningSnapshot())
        var invalid = try decode(legacyData.merging(["snapshot_version": 4, "lessons": [lesson]]) { _, value in value })
        invalid.snapshotVersion = 3
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertThrowsError(try JSONEncoder().encode(invalid))
        invalid.snapshotVersion = LearningSnapshot.currentSnapshotVersion + 1
        invalid.prepareForLocalMutation()
        XCTAssertThrowsError(try invalid.validate())
    }

    func testRejectsDuplicateIdentitiesInvalidFieldsAndBrokenLinksOnRead() throws {
        var payload = legacyData
        payload["snapshot_version"] = 4
        payload["lessons"] = [lesson]
        XCTAssertNoThrow(try decode(payload))
        for changes: [String: Any] in [
            ["title": ""], ["title": "  Введение"], ["course": " "], ["course": "Без курса"],
            ["source_url": "ftp://example.org"], ["source_url": "relative"], ["source_url": "https:///video"],
            ["card_ids": [cardID, cardID]], ["card_ids": [otherID]], ["card_ids": NSNull()], ["card_ids": ["не UUID"]]
        ] {
            payload["lessons"] = [lesson.merging(changes) { _, value in value }]
            XCTAssertThrowsError(try decode(payload), "\(changes)")
        }
        let missingMembership = lesson.filter { $0.key != "card_ids" }
        payload["lessons"] = [missingMembership]
        XCTAssertThrowsError(try decode(payload))
        payload["lessons"] = [lesson, lesson.merging(["title": "Другое"]) { _, value in value }]
        XCTAssertThrowsError(try decode(payload))
        payload["lessons"] = [lesson, lesson.merging(["id": otherID]) { _, value in value }]
        XCTAssertThrowsError(try decode(payload))
        let inAnotherCourse = lesson.merging(["id": otherID, "course": "Python"]) { _, value in value }
        payload["lessons"] = [lesson, inAnotherCourse]
        XCTAssertEqual(try decode(payload).lessons.count, 2)
    }
}
