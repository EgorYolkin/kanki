import XCTest
@testable import Kanki

final class CardSchedulingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNewCardRatingOrdersNextDueDates() throws {
        let schedules = try RecallRating.allCases.map {
            try CardScheduling.nextReview(for: nil, rating: $0, at: now)
        }

        let dues = schedules.map(\.due)
        XCTAssertEqual(dues, dues.sorted())
        XCTAssertEqual(Set(dues).count, RecallRating.allCases.count)
        XCTAssertEqual(schedules.map(\.reps), Array(repeating: 1, count: 4))
        XCTAssertEqual(schedules.map(\.state), [.learning, .learning, .learning, .review])
    }

    func testSuccessfulReviewsKeepGrowingTheInterval() throws {
        var schedule: CardSchedule?
        var reviewDate = now
        var intervals: [Double] = []

        for _ in 0..<4 {
            schedule = try CardScheduling.nextReview(for: schedule, rating: .good, at: reviewDate)
            reviewDate = try XCTUnwrap(schedule?.due)
            intervals.append(try XCTUnwrap(schedule?.scheduledDays))
        }

        for (earlier, later) in zip(intervals, intervals.dropFirst()) {
            XCTAssertLessThan(earlier, later)
        }
    }

    func testAgainOnReviewCardEntersRelearningAndCountsLapse() throws {
        let learned = try CardScheduling.nextReview(for: nil, rating: .good, at: now)
        let reviewed = try CardScheduling.nextReview(for: learned, rating: .good, at: learned.due)
        XCTAssertEqual(reviewed.state, .review)
        XCTAssertEqual(reviewed.lapses, 0)

        let relearning = try CardScheduling.nextReview(for: reviewed, rating: .again, at: reviewed.due)

        XCTAssertEqual(relearning.state, .relearning)
        XCTAssertEqual(relearning.lapses, 1)
        XCTAssertEqual(
            relearning.due.timeIntervalSince(reviewed.due),
            5 * 60,
            accuracy: 1
        )
    }

    func testHardAndEasyAfterReviewStayInReview() throws {
        let learned = try CardScheduling.nextReview(for: nil, rating: .good, at: now)
        let reviewed = try CardScheduling.nextReview(for: learned, rating: .good, at: learned.due)

        let hard = try CardScheduling.nextReview(for: reviewed, rating: .hard, at: reviewed.due)
        let easy = try CardScheduling.nextReview(for: reviewed, rating: .easy, at: reviewed.due)

        XCTAssertEqual(hard.state, .review)
        XCTAssertEqual(easy.state, .review)
        XCTAssertGreaterThan(easy.scheduledDays, hard.scheduledDays)
    }
}
