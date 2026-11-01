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
        let card = SessionCard(id: id, question: "Что такое Km?", answer: "Константа Михаэлиса")

        XCTAssertEqual(card.id, id)
        XCTAssertEqual(card.question, "Что такое Km?")
        XCTAssertEqual(card.answer, "Константа Михаэлиса")
        XCTAssertEqual(card, SessionCard(id: id, question: "Что такое Km?", answer: "Константа Михаэлиса"))
    }
}
