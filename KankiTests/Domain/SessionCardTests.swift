import XCTest
@testable import Kanki

final class SessionCardTests: XCTestCase {
    func testCardsGetDistinctIdentities() {
        let first = SessionCard(question: "Вопрос", answer: "Ответ")
        let second = SessionCard(question: "Вопрос", answer: "Ответ")

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
    }

    func testCardKeepsFieldsAndInjectedIdentity() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let card = SessionCard(id: id, question: "Что такое Km?", answer: "Константа Михаэлиса", createdAt: createdAt)

        XCTAssertEqual(card.id, id)
        XCTAssertEqual(card.question, "Что такое Km?")
        XCTAssertEqual(card.answer, "Константа Михаэлиса")
        XCTAssertEqual(card.createdAt, createdAt)
        XCTAssertEqual(
            card,
            SessionCard(id: id, question: "Что такое Km?", answer: "Константа Михаэлиса", createdAt: createdAt)
        )
    }
}
