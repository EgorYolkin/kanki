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
}
