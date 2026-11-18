import XCTest
@testable import Kanki

final class NewlineCorrectionTests: XCTestCase {
    func testPreviewReplacesOnlySelectedPairAndLeavesDraftUntouched() {
        let source = "Путь C:\\new\r\n🙂 Ошибка\\nдалее\\t"
        var draft = CardDraft(question: source, answer: #"код \n"#)
        var correction = NewlineCorrection(source: draft.question)
        XCTAssertEqual(correction.matches.map(\.id), [0, 1])
        XCTAssertTrue(correction.matches[0].context.contains(#"C:⟦\n⟧ew"#))
        XCTAssertTrue(correction.selected.isEmpty)
        XCTAssertEqual(correction.preview, source)

        correction.selected = [1]
        XCTAssertEqual(correction.preview, "Путь C:\\new\r\n🙂 Ошибка\nдалее\\t")
        XCTAssertEqual(draft.question, source)
        let reopened = NewlineCorrection(source: draft.question)
        XCTAssertTrue(reopened.selected.isEmpty)
        XCTAssertEqual(reopened.preview, source)

        draft.question = correction.preview
        XCTAssertEqual(draft.answer, #"код \n"#)
        XCTAssertEqual(NewlineCorrection(source: draft.question).matches.count, 1)
    }

    func testAdjacentPairsAtBoundariesAndRealLineBreaks() {
        var correction = NewlineCorrection(source: #"\n\n"#)
        correction.selected = Set(correction.matches.map(\.id))
        XCTAssertEqual(correction.preview, "\n\n")
        for source in ["", "\r\n", "а\nб", #"\t"#] {
            let clean = NewlineCorrection(source: source)
            XCTAssertTrue(clean.matches.isEmpty)
            XCTAssertEqual(clean.preview, source)
        }
    }
}
