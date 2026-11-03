import XCTest
@testable import Kanki

final class CardDraftTests: XCTestCase {
    func testEmptyDraftCannotBeSubmitted() {
        let draft = CardDraft()

        XCTAssertFalse(draft.canSubmit)
        XCTAssertNil(draft.makeCard())
    }

    func testWhitespaceOnlyFieldsCannotBeSubmitted() {
        let draft = CardDraft(question: "  \n ", answer: "\t")

        XCTAssertFalse(draft.canSubmit)
        XCTAssertNil(draft.makeCard())
    }

    func testBothFieldsRequired() {
        XCTAssertFalse(CardDraft(question: "Вопрос", answer: "").canSubmit)
        XCTAssertFalse(CardDraft(question: "", answer: "Ответ").canSubmit)
        XCTAssertTrue(CardDraft(question: "Вопрос", answer: "Ответ").canSubmit)
    }

    func testTrimming() {
        let draft = CardDraft(question: "  Почему небо голубое? \n", answer: "\t Рассеяние света  ")

        XCTAssertEqual(draft.trimmedQuestion, "Почему небо голубое?")
        XCTAssertEqual(draft.trimmedAnswer, "Рассеяние света")

        let card = draft.makeCard()
        XCTAssertEqual(card?.question, "Почему небо голубое?")
        XCTAssertEqual(card?.answer, "Рассеяние света")
    }

    func testEditingKeepsIdentityAndRejectsEmptyQuestion() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let card = SessionCard(
            id: id,
            question: "Старый вопрос",
            answer: "Старый ответ",
            createdAt: createdAt,
            deck: "Математика",
            isArchived: true
        )

        var draft = CardDraft(card: card)
        XCTAssertEqual(draft.question, "Старый вопрос")
        XCTAssertEqual(draft.answer, "Старый ответ")
        XCTAssertEqual(draft.deck, "Математика")

        draft.question = "  Новый вопрос  "
        draft.answer = "Новый ответ "
        draft.deck = " Физика "
        let updated = draft.updated(card)

        XCTAssertEqual(updated?.id, id)
        XCTAssertEqual(updated?.createdAt, createdAt)
        XCTAssertEqual(updated?.question, "Новый вопрос")
        XCTAssertEqual(updated?.answer, "Новый ответ")
        XCTAssertEqual(updated?.deck, "Физика")
        XCTAssertEqual(updated?.isArchived, true)

        draft.question = "   "
        XCTAssertNil(draft.updated(card))
    }
}
