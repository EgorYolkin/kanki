import Foundation
import XCTest
@testable import Kanki

final class CardTextRoundTripTests: XCTestCase {
    func testEditStoreAndCardExportPreserveExactUTF8() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "kanki.sqlite")
        let original = SessionCard(question: "Вопрос", answer: "Ответ")
        let question = "    Заголовок\r\n\r\n**вопрос**\n"
        let answer = "    код \\n\n\n    ещё\n"
        var draft = CardDraft(card: original)
        draft.question = question
        draft.answer = answer
        let edited = try XCTUnwrap(draft.updated(original))
        try LocalCardStore.save(LearningSnapshot(cards: [edited]), to: url)

        let reopened = try LocalCardStore.load(from: url)
        let exported = try CardExportArchive.decode(CardExportArchive(snapshot: reopened).encoded())
        for cards in [reopened.cards, exported.cards] {
            let card = try XCTUnwrap(cards.first)
            XCTAssertEqual(card.id, original.id)
            XCTAssertEqual(Data(card.question.utf8), Data(question.utf8))
            XCTAssertEqual(Data(card.answer.utf8), Data(answer.utf8))
        }
    }
}
