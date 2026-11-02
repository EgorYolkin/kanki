import Foundation
import XCTest
@testable import Kanki

final class CardExportArchiveTests: XCTestCase {
    func testExistingStoreKeepsCardIdentityAndReviewTime() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000)
        let secondTime = Date(timeIntervalSince1970: 1_800_000_030)
        let first = SessionCard(question: "Первый", answer: "Ответ", createdAt: firstTime)
        let second = SessionCard(question: "Второй", answer: "Ответ", createdAt: secondTime)
        let snapshot = LearningSnapshot(
            cards: [first, second],
            reviews: [
                SessionReview(cardID: first.id, rating: .good, reviewedAt: firstTime),
                SessionReview(cardID: second.id, rating: .hard, reviewedAt: secondTime),
                SessionReview(cardID: first.id, rating: .again, reviewedAt: secondTime)
            ]
        )
        try LocalCardStore.save(snapshot, to: fileURL)

        let reopened = try LocalCardStore.load(from: fileURL)
        XCTAssertEqual(reopened.cards, snapshot.cards)
        XCTAssertEqual(reopened.reviews.map(\.cardID), [first.id, second.id, first.id])
        XCTAssertEqual(reopened.reviews.map(\.rating), [.good, .hard, .again])
        XCTAssertEqual(reopened.reviews.map(\.reviewedAt), [firstTime, secondTime, secondTime])
        XCTAssertEqual(try CardExportArchive.decode(CardExportArchive(snapshot: reopened).encoded()).reviews,
                       reopened.reviews)
    }

    func testSingleAndMultipleSelectionExcludeUnselectedReviews() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SessionCard(question: "Альфа", answer: "Ответ А", createdAt: now)
        let second = SessionCard(question: "Бета", answer: "Ответ Б", createdAt: now)
        let third = SessionCard(question: "Гамма", answer: "Ответ В", createdAt: now)
        let snapshot = LearningSnapshot(cards: [first, second, third], reviews: [
            SessionReview(cardID: first.id, rating: .good, reviewedAt: now),
            SessionReview(cardID: second.id, rating: .hard, reviewedAt: now),
            SessionReview(cardID: first.id, rating: .again, reviewedAt: now),
            SessionReview(cardID: third.id, rating: .easy, reviewedAt: now)
        ])

        let single = try CardExportArchive.decode(
            CardExportArchive(snapshot: snapshot, selectedIDs: [first.id]).encoded()
        )
        XCTAssertEqual(single.formatVersion, 1)
        XCTAssertEqual(single.cards, [first])
        XCTAssertEqual(single.reviews.map(\.rating), [.good, .again])
        let contents = try XCTUnwrap(String(bytes: single.encoded(), encoding: .utf8))
        XCTAssertFalse(contents.contains("Бета"))

        let multiple = try CardExportArchive.decode(
            CardExportArchive(snapshot: snapshot, selectedIDs: [first.id, third.id]).encoded()
        )
        XCTAssertEqual(multiple.cards, [first, third])
        XCTAssertEqual(multiple.reviews.map(\.cardID), [first.id, first.id, third.id])

        let all = try CardExportArchive.decode(CardExportArchive(snapshot: snapshot).encoded())
        XCTAssertEqual(all.cards, [first, second, third])
        XCTAssertEqual(all.reviews.map(\.cardID), [first.id, second.id, first.id, third.id])
    }

    func testUnknownExportFormatIsRejected() throws {
        let data = try CardExportArchive(snapshot: LearningSnapshot()).encoded()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload["formatVersion"] = 2
        let unsupported = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try CardExportArchive.decode(unsupported))
    }

    func testDamagedOrOrphanedStoreCannotBeReadAsEmpty() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = Data("broken".utf8)
        try damaged.write(to: fileURL)
        XCTAssertThrowsError(try LocalCardStore.load(from: fileURL))
        XCTAssertEqual(try Data(contentsOf: fileURL), damaged)

        let orphan = LearningSnapshot(cards: [], reviews: [
            SessionReview(cardID: UUID(), rating: .good, reviewedAt: Date())
        ])
        try LocalCardStore.save(orphan, to: fileURL)
        XCTAssertThrowsError(try LocalCardStore.load(from: fileURL))
    }

    func testWriteFailureDoesNotPretendDataWasSaved() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocking parent directory".utf8).write(to: directory)
        XCTAssertThrowsError(try LocalCardStore.save(
            LearningSnapshot(cards: [SessionCard(question: "Новая", answer: "Карточка")]),
            to: fileURL
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeStoreLocation() -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, directory.appendingPathComponent("cards.json"))
    }
}
