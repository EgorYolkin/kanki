import XCTest
@testable import Kanki

final class SessionLogTests: XCTestCase {
    func testEmptyLog() {
        let log = SessionLog()

        XCTAssertEqual(log.count, 0)
        XCTAssertNil(log.lastRating)
        XCTAssertEqual(log.reviews, [])
    }

    func testRecordAppendsInOrderAndTracksLastRating() {
        let card = SessionCard(question: "Вопрос", answer: "Ответ")
        let other = SessionCard(question: "Другой", answer: "Ответ")
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        var log = SessionLog()

        log.record(card, rating: .good, at: firstDate)
        log.record(other, rating: .again, at: secondDate)

        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.lastRating, .again)
        XCTAssertEqual(log.reviews, [
            SessionReview(cardID: card.id, rating: .good, reviewedAt: firstDate),
            SessionReview(cardID: other.id, rating: .again, reviewedAt: secondDate)
        ])
    }

    func testCardHistoryAndFailedWriteRollback() {
        let card = SessionCard(question: "Вопрос", answer: "Ответ")
        let other = SessionCard(question: "Другой", answer: "Ответ")
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        let third = Date(timeIntervalSince1970: 3_000)
        var log = SessionLog()

        log.record(card, rating: .good, at: first)
        log.record(other, rating: .hard, at: second)
        log.record(card, rating: .again, at: third)
        XCTAssertEqual(log.history(for: card.id).map(\.rating), [.again, .good])
        XCTAssertEqual(log.history(for: card.id).map(\.reviewedAt), [third, first])

        log.discardLastRecord()
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.lastRating, .hard)
        XCTAssertEqual(log.history(for: card.id).map(\.rating), [.good])
    }
}
