import XCTest
@testable import Kanki

final class StatisticsOverviewTests: XCTestCase {
    func testSundayAtYearBoundaryEndsFirstWeekAndLabelsMonday() throws {
        let days = ["2023-12-31", "2024-01-01", "2024-01-02", "2024-01-03"].map {
            StudyStatistics.Day(date: $0, visits: 1, reviews: 0)
        }
        let overview = try StatisticsOverview(statistics(days: days))

        XCTAssertEqual(overview.weeks.map(\.leadingBlanks), [6, 0])
        XCTAssertEqual(overview.weeks.map { $0.days.count }, [1, 3])
        XCTAssertEqual(overview.weeks.flatMap { $0.days.map(\.date) }, days.map(\.date))
        XCTAssertNil(overview.weeks[0].monthLabel)
        XCTAssertNotNil(overview.weeks[1].monthLabel)
        XCTAssertFalse(overview.isEmpty, "Визиты без повторений видны в отчёте")
    }

    func testMondayStartsNewColumnWithoutBlanks() throws {
        let days = (1...8).map { StudyStatistics.Day(date: "2024-01-0\($0)", visits: 0, reviews: 0) }
        let overview = try StatisticsOverview(statistics(days: days))

        XCTAssertEqual(overview.weeks.map(\.leadingBlanks), [0, 0])
        XCTAssertEqual(overview.weeks.map { $0.days.count }, [7, 1])
        XCTAssertNotNil(overview.weeks[0].monthLabel)
        XCTAssertNil(overview.weeks[1].monthLabel)
        XCTAssertTrue(overview.isEmpty)
    }

    func testHistoricalReviewsRemainVisibleAndTopicsShareScale() throws {
        let topics = [StudyStatistics.Topic(name: "Первая", count: 2), .init(name: "Вторая", count: 3)]
        let input = StudyStatistics(totalReviews: 5, streakDays: 0, days: [], ratings: [0, 0, 5, 0], topics: topics)
        let overview = try StatisticsOverview(input)

        XCTAssertFalse(overview.isEmpty)
        XCTAssertTrue(overview.weeks.isEmpty)
        XCTAssertEqual(overview.largestTopicCount, 3)
    }

    func testMissingRatingOrInvalidCalendarDateIsNotAZeroReport() {
        XCTAssertThrowsError(try StatisticsOverview(statistics(days: [], ratings: [0, 0, 0])))
        XCTAssertThrowsError(try StatisticsOverview(statistics(days: [.init(date: "не дата", visits: 0, reviews: 0)])))
    }

    func testHeatmapIntensityUsesStableBands() {
        let counts = [0, 1, 2, 4, 5, 9, 10, 100]
        XCTAssertEqual(counts.map(StatisticsOverview.intensity(for:)), [0, 0.3, 0.5, 0.5, 0.75, 0.75, 1, 1])
    }

    private func statistics(days: [StudyStatistics.Day], ratings: [Int] = [0, 0, 0, 0]) -> StudyStatistics {
        StudyStatistics(totalReviews: 0, streakDays: 0, days: days, ratings: ratings, topics: [])
    }
}
