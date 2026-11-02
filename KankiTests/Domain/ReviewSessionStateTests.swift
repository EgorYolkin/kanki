import XCTest
@testable import Kanki

final class ReviewSessionStateTests: XCTestCase {
    private let first = SessionCard(question: "Первый", answer: "A")
    private let second = SessionCard(question: "Второй", answer: "B")

    func testEmptyQueueIsFinished() {
        let session = ReviewSessionState(cards: [])

        XCTAssertNil(session.currentCard)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.reviewedCount, 0)
        XCTAssertEqual(session.summaryRows.map(\.rating), [])
        XCTAssertFalse(session.isAnswerVisible)
    }

    func testAnswerIsHiddenUntilRevealed() {
        var session = ReviewSessionState(cards: [first])

        XCTAssertFalse(session.isAnswerVisible)
        session.revealAnswer()
        XCTAssertTrue(session.isAnswerVisible)
    }

    func testQueueAdvancesAndRecordsReviews() {
        var session = ReviewSessionState(cards: [first, second])
        let date = Date(timeIntervalSince1970: 500)

        XCTAssertEqual(session.currentCard, first)
        XCTAssertEqual(session.progressText, "Карточка 1 из 2")

        session.revealAnswer()
        let firstReview = session.record(.good, at: date)

        XCTAssertEqual(firstReview?.cardID, first.id)
        XCTAssertEqual(firstReview?.rating, .good)
        XCTAssertEqual(firstReview?.reviewedAt, date)
        XCTAssertFalse(session.isAnswerVisible)
        XCTAssertEqual(session.currentCard, second)
        XCTAssertEqual(session.progressText, "Карточка 2 из 2")

        session.revealAnswer()
        XCTAssertNotNil(session.record(.again, at: date))

        XCTAssertNil(session.currentCard)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.reviewedCount, 2)
        XCTAssertEqual(session.summaryRows.map(\.rating), [.again, .good])
        XCTAssertEqual(session.summaryRows.map(\.count), [1, 1])
    }

    func testCountsAccumulatePerRating() {
        var session = ReviewSessionState(cards: [first, second])

        _ = session.record(.good)
        _ = session.record(.good)

        XCTAssertEqual(session.summaryRows.count, 1)
        XCTAssertEqual(session.summaryRows.first?.rating, .good)
        XCTAssertEqual(session.summaryRows.first?.count, 2)
    }

    func testRecordAfterFinishIsIgnored() {
        var session = ReviewSessionState(cards: [first])
        _ = session.record(.easy)

        XCTAssertNil(session.record(.again))
        XCTAssertEqual(session.counts, [.easy: 1])
        XCTAssertEqual(session.reviewedCount, 1)
        XCTAssertTrue(session.isFinished)
    }

    func testProgressTextIsClampedToCardCount() {
        var session = ReviewSessionState(cards: [first])

        _ = session.record(.hard)

        XCTAssertEqual(session.progressText, "Карточка 1 из 1")
    }
}
