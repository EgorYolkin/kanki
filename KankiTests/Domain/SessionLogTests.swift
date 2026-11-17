import XCTest
@testable import Kanki

final class SessionLogTests: XCTestCase {
    func testEmptyLog() {
        let log = SessionLog()

        XCTAssertEqual(log.count, 0)
        XCTAssertNil(log.lastRating)
        XCTAssertEqual(log.reviews, [])
    }

    func testRestoredReviewsTrackCountAndLastRating() {
        let card = SessionCard(question: "Вопрос", answer: "Ответ")
        let other = SessionCard(question: "Другой", answer: "Ответ")
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        let log = SessionLog(reviews: [
            SessionReview(cardID: card.id, rating: .good, reviewedAt: firstDate),
            SessionReview(cardID: other.id, rating: .again, reviewedAt: secondDate)
        ])

        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.lastRating, .again)
        XCTAssertEqual(log.reviews, [
            SessionReview(cardID: card.id, rating: .good, reviewedAt: firstDate),
            SessionReview(cardID: other.id, rating: .again, reviewedAt: secondDate)
        ])
    }

    func testCardHistoryIsNewestFirstAndExcludesOtherCards() {
        let card = SessionCard(question: "Вопрос", answer: "Ответ")
        let other = SessionCard(question: "Другой", answer: "Ответ")
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        let third = Date(timeIntervalSince1970: 3_000)
        let log = SessionLog(reviews: [
            SessionReview(cardID: card.id, rating: .good, reviewedAt: first),
            SessionReview(cardID: other.id, rating: .hard, reviewedAt: second),
            SessionReview(cardID: card.id, rating: .again, reviewedAt: third)
        ])
        XCTAssertEqual(log.history(for: card.id).map(\.rating), [.again, .good])
        XCTAssertEqual(log.history(for: card.id).map(\.reviewedAt), [third, first])
    }
}
