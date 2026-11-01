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
}
