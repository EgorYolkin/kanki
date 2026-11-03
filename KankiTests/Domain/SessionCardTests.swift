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

    func testDeckIsTrimmedAndBlankMeansNoCategory() {
        XCTAssertNil(SessionCard(question: "q", answer: "a", deck: "  ").deck)
        XCTAssertEqual(SessionCard(question: "q", answer: "a", deck: " Математика ").deck, "Математика")
    }

    func testLegacyCardWithoutDeckDecodesAndDeckOmittedWhenNil() throws {
        let id = "2621F15A-306C-435A-9680-AEEB602F272D"
        let legacy = Data(
            """
            {"id":"\(id)","question":"annals","answer":"bsbs","createdAt":100}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(SessionCard.self, from: legacy)
        XCTAssertNil(decoded.deck)

        let encoded = try String(bytes: JSONEncoder().encode(decoded), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains("\"deck\""))

        let withDeck = try String(
            bytes: JSONEncoder().encode(
                SessionCard(question: "q", answer: "a", createdAt: decoded.createdAt, deck: "Физика")
            ),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(withDeck.contains("\"deck\":\"Физика\""))
    }

}
