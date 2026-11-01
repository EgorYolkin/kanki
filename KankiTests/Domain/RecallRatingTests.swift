import SwiftUI
import XCTest
@testable import Kanki

final class RecallRatingTests: XCTestCase {
    func testRawValuesFollowButtonOrder() {
        XCTAssertEqual(RecallRating.allCases.map(\.rawValue), [1, 2, 3, 4])
        XCTAssertEqual(RecallRating.again.rawValue, 1)
        XCTAssertEqual(RecallRating.hard.rawValue, 2)
        XCTAssertEqual(RecallRating.good.rawValue, 3)
        XCTAssertEqual(RecallRating.easy.rawValue, 4)
        XCTAssertEqual(RecallRating(rawValue: 3), .good)
        XCTAssertNil(RecallRating(rawValue: 0))
    }

    func testTitles() {
        XCTAssertEqual(RecallRating.again.title, "Снова")
        XCTAssertEqual(RecallRating.hard.title, "Трудно")
        XCTAssertEqual(RecallRating.good.title, "Хорошо")
        XCTAssertEqual(RecallRating.easy.title, "Легко")
    }

    func testTints() {
        XCTAssertEqual(RecallRating.again.tint, .red)
        XCTAssertEqual(RecallRating.hard.tint, .orange)
        XCTAssertEqual(RecallRating.good.tint, .green)
        XCTAssertEqual(RecallRating.easy.tint, .blue)
    }
}
