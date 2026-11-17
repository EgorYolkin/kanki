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

    func testRecordUpdatesOnlyRatedCardAndPreservesExistingHistory() throws {
        let card = SessionCard(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            question: "Вопрос",
            answer: "Ответ",
            createdAt: now
        )
        let other = SessionCard(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            question: "Другой вопрос",
            answer: "Другой ответ",
            createdAt: now
        )
        let initialSchedule = try CardScheduling.nextReview(for: nil, rating: .good, at: now)
        let earlierReview = SessionReview(cardID: other.id, rating: .good, reviewedAt: now)
        var snapshot = LearningSnapshot(
            cards: [card, other],
            reviews: [earlierReview],
            schedules: [card.id: initialSchedule, other.id: initialSchedule]
        )

        try CardScheduling.record(card, rating: .easy, in: &snapshot, at: initialSchedule.due)

        XCTAssertEqual(snapshot.cards, [card, other])
        XCTAssertEqual(snapshot.reviews, [
            earlierReview,
            SessionReview(cardID: card.id, rating: .easy, reviewedAt: initialSchedule.due)
        ])
        XCTAssertEqual(snapshot.schedules[card.id]?.reps, initialSchedule.reps + 1)
        XCTAssertEqual(snapshot.schedules[other.id], initialSchedule)
    }

    func testRemovedArchivedOrEditedCardCannotMutateReplacementSnapshot() throws {
        let card = SessionCard(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            question: "Старый вопрос",
            answer: "Старый ответ",
            createdAt: now,
            deck: "Колода"
        )
        let schedule = try CardScheduling.nextReview(for: nil, rating: .good, at: now)
        let review = SessionReview(cardID: card.id, rating: .good, reviewedAt: now)
        var archived = card
        archived.isArchived = true
        let edited = SessionCard(
            id: card.id,
            question: "Новый вопрос",
            answer: "Новый ответ",
            createdAt: now,
            deck: card.deck
        )
        var moved = card
        moved.deck = "Другая колода"
        let replacements = [
            LearningSnapshot(),
            LearningSnapshot(cards: [archived], reviews: [review], schedules: [card.id: schedule]),
            LearningSnapshot(cards: [edited], reviews: [review], schedules: [card.id: schedule]),
            LearningSnapshot(cards: [moved], reviews: [review], schedules: [card.id: schedule])
        ]

        for original in replacements {
            var snapshot = original

            XCTAssertThrowsError(try CardScheduling.record(card, rating: .again, in: &snapshot, at: now)) { error in
                XCTAssertTrue(error is CardReviewError)
            }
            XCTAssertEqual(snapshot, original, "Отклонённая оценка не меняет историю или расписание")
        }

        var snapshot = LearningSnapshot(cards: [archived])
        XCTAssertThrowsError(try CardScheduling.record(archived, rating: .again, in: &snapshot, at: now))
        XCTAssertEqual(snapshot, LearningSnapshot(cards: [archived]))
    }
}
