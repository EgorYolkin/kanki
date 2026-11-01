import XCTest
@testable import Kanki

final class CardSearchTests: XCTestCase {
    private let cards = [
        SessionCard(question: "Почему небо голубое?", answer: "Рассеяние света"),
        SessionCard(question: "Что такое Km?", answer: "Концентрация при половине Vmax")
    ]

    func testEmptyQueryReturnsEveryCard() {
        XCTAssertEqual(CardSearch.filter(cards, matching: "   ").count, 2)
    }

    func testMatchesQuestionCaseInsensitively() {
        let result = CardSearch.filter(cards, matching: "НЕБО")
        XCTAssertEqual(result.map(\.question), ["Почему небо голубое?"])
    }

    func testMatchesAnswer() {
        let result = CardSearch.filter(cards, matching: "vmax")
        XCTAssertEqual(result.map(\.question), ["Что такое Km?"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(CardSearch.filter(cards, matching: "граф").isEmpty)
    }
}
