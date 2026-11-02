import Foundation
import XCTest
@testable import Kanki

@MainActor
final class CardLibraryTests: XCTestCase {
    func testReviewsKeepCardIdentityRatingAndTimeAfterReload() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = CardLibrary(fileURL: fileURL)
        try library.add(question: "Первый вопрос", answer: "Первый ответ")
        try library.add(question: "Второй вопрос", answer: "Второй ответ")
        let first = try XCTUnwrap(library.cards.first)
        let second = try XCTUnwrap(library.cards.last)
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000.123)
        let secondTime = Date(timeIntervalSince1970: 1_800_000_030.456)
        try library.record(first, rating: .good, at: firstTime)
        try library.record(second, rating: .hard, at: secondTime)
        try library.record(first, rating: .again, at: secondTime)

        let reopened = CardLibrary(fileURL: fileURL)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.cards, [first, second])
        XCTAssertEqual(reopened.reviews.map(\.cardID), [first.id, second.id, first.id])
        XCTAssertEqual(reopened.reviews.map(\.rating), [.good, .hard, .again])
        XCTAssertEqual(reopened.history(for: first.id).map(\.rating), [.again, .good])
        XCTAssertEqual(reopened.reviews[0].reviewedAt.timeIntervalSince1970,
                       firstTime.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(reopened.reviews[1].reviewedAt.timeIntervalSince1970,
                       secondTime.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSingleAndMultipleSelectionExcludeUnselectedCardReviews() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = CardLibrary(fileURL: fileURL)
        try library.add(question: "Альфа", answer: "Ответ А")
        try library.add(question: "Бета", answer: "Ответ Б")
        try library.add(question: "Гамма", answer: "Ответ В")
        let first = try XCTUnwrap(library.cards.first)
        let second = library.cards[1]
        let third = try XCTUnwrap(library.cards.last)
        try library.record(first, rating: .good)
        try library.record(second, rating: .hard)
        try library.record(first, rating: .again)
        try library.record(third, rating: .easy)

        let selected = try CardArchive.decode(library.export(selectedIDs: [first.id]).encoded())
        XCTAssertEqual(selected.formatVersion, 1)
        XCTAssertEqual(selected.cards, [first])
        XCTAssertEqual(selected.reviews.map(\.cardID), [first.id, first.id])
        XCTAssertEqual(selected.reviews.map(\.rating), [.good, .again])
        XCTAssertFalse(String(decoding: try selected.encoded(), as: UTF8.self).contains("Бета"))

        let multiple = try CardArchive.decode(library.export(selectedIDs: [first.id, third.id]).encoded())
        XCTAssertEqual(multiple.cards, [first, third])
        XCTAssertEqual(multiple.reviews.map(\.cardID), [first.id, first.id, third.id])
        XCTAssertEqual(multiple.reviews.map(\.rating), [.good, .again, .easy])

        let all = try CardArchive.decode(library.export().encoded())
        XCTAssertEqual(all.cards, [first, second, third])
        XCTAssertEqual(all.reviews.map(\.cardID), [first.id, second.id, first.id, third.id])
    }

    func testCorruptStoreDoesNotGetOverwritten() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("damaged".utf8)
        try original.write(to: fileURL)

        let library = CardLibrary(fileURL: fileURL)
        XCTAssertNotNil(library.loadError)
        XCTAssertThrowsError(try library.add(question: "Новая", answer: "Карточка"))
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertTrue(library.cards.isEmpty)
    }

    func testWriteFailureDoesNotAcceptCardOrReview() throws {
        let (directory, fileURL) = makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CardLibrary(fileURL: fileURL)
        try library.add(question: "Сохранили", answer: "Ответ")
        let card = try XCTUnwrap(library.cards.first)

        try FileManager.default.removeItem(at: directory)
        try Data("blocking parent directory".utf8).write(to: directory)
        XCTAssertThrowsError(try library.record(card, rating: .easy))
        XCTAssertEqual(library.reviews.count, 0)
        XCTAssertThrowsError(try library.add(question: "Нельзя", answer: "Записать"))
        XCTAssertEqual(library.cards, [card])
    }

    private func makeStoreLocation() -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, directory.appendingPathComponent("cards.json"))
    }
}
