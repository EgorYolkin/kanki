import XCTest
@testable import Kanki

final class LessonDraftTests: XCTestCase {
    func testNormalizesInputWithoutFoldingCase() {
        let draft = LessonDraft(title: "  Введение\n", course: "  sWift\t", source: " https://example.org/video?part=2\n")
        XCTAssertEqual(draft.normalizedTitle, "Введение")
        XCTAssertEqual(draft.normalizedCourse, "sWift")
        XCTAssertEqual(draft.sourceURL?.absoluteString, "https://example.org/video?part=2")
        XCTAssertNil(draft.validationError)
    }

    func testBlankCourseAndURLAreOptionalButTitleIsRequired() {
        var draft = LessonDraft(title: "Один", course: " \n", source: "\t")
        XCTAssertNil(draft.normalizedCourse)
        XCTAssertNil(draft.sourceURL)
        XCTAssertNil(draft.validationError)
        draft.title = " \n"
        XCTAssertNotNil(draft.validationError)
        draft.title = "Два"
        draft.course = " Без курса "
        XCTAssertNotNil(draft.validationError)
    }

    func testSourceRequiresAbsoluteHTTPOrHTTPSAndHost() {
        var draft = LessonDraft(title: "Урок", course: nil, source: "")
        for source in ["video", "//example.org/video", "ftp://example.org", "https:///path", "https://bad host", "https://bad%20host"] {
            draft.source = source
            XCTAssertNil(draft.sourceURL, source)
            XCTAssertNotNil(draft.validationError, source)
        }
        draft.source = "HTTP://example.org:8080/видео"
        XCTAssertNotNil(draft.sourceURL)
        XCTAssertNil(draft.validationError)
    }
}
