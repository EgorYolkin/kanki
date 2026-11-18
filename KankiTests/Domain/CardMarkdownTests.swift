import Foundation
import XCTest
@testable import Kanki

final class CardMarkdownTests: XCTestCase {
    func testHeadingsParagraphsAndNestedEmphasis() throws {
        let markdown = CardMarkdown(source: "## Заголовок\n\nТекст с ***выделением***.\n\nКонец.")
        XCTAssertEqual(markdown.blocks.count, 3)
        XCTAssertEqual(markdown.blocks.first, .heading(level: 2, text: AttributedString("Заголовок")))
        let text = try paragraph(in: markdown, at: 1)
        XCTAssertEqual(String(text.characters), "Текст с выделением.")
        let word = try XCTUnwrap(text.range(of: "выделением"))
        XCTAssertEqual(text[word].inlinePresentationIntent, [.stronglyEmphasized, .emphasized])
        XCTAssertEqual(markdown.blocks.last, .paragraph(AttributedString("Конец.")))
        XCTAssertEqual(markdown.preview, "Заголовок Текст с выделением. Конец.")
    }

    func testLineBreaksAndLiteralEscapes() throws {
        let markdown = CardMarkdown(source: "один\r\nдва  \r\nтри\\nчетыре")
        let text = try paragraph(in: markdown)
        XCTAssertEqual(String(text.characters), "один\nдва\nтри\\nчетыре")
        XCTAssertEqual(markdown.preview, "один два три\\nчетыре")
    }

    func testOrderedAndNestedListsPreserveNumbersAndOrder() {
        let markdown = CardMarkdown(source: "4. Четыре\n   - Внутри\n5. Пять")
        XCTAssertEqual(markdown.blocks, [
            .list(start: 4, items: [
                [.paragraph(AttributedString("Четыре")), .list(start: nil, items: [[.paragraph(AttributedString("Внутри"))]])],
                [.paragraph(AttributedString("Пять"))]
            ])
        ])
        XCTAssertEqual(markdown.preview, "Четыре Внутри Пять")
    }

    func testInlineAndFencedCodeAreLiteral() throws {
        let literal = #"**жирный?**\n"#
        let markdown = CardMarkdown(source: "Код `\(literal)`\n\n```text\n  \(literal)\n```")
        let text = try paragraph(in: markdown)
        let code = try XCTUnwrap(text.range(of: literal))
        XCTAssertEqual(text[code].inlinePresentationIntent, .code)
        XCTAssertEqual(markdown.blocks.last, .code("  \(literal)\n"))
        XCTAssertEqual(markdown.preview, "Код \(literal) \(literal)")
    }

    func testUnclosedFenceDoesNotDiscardRemainder() {
        let markdown = CardMarkdown(source: "До\n\n```\n# всё ещё видно\n\nостаток")
        XCTAssertEqual(markdown.blocks.last, .code("# всё ещё видно\n\nостаток\n"))
    }

    func testOnlyAbsoluteWebLinksHaveLinkAttributes() throws {
        let source = "[**веб**](https://example.org/a) [http](http://example.org) "
            + "[письмо](mailto:a@example.org) [путь](../p) [хост](https:/p)"
        let markdown = CardMarkdown(source: source)
        let text = try paragraph(in: markdown)
        let web = try XCTUnwrap(text.range(of: "веб"))
        XCTAssertEqual(text[web].link?.absoluteString, "https://example.org/a")
        XCTAssertEqual(text[web].inlinePresentationIntent, .stronglyEmphasized)
        let http = try XCTUnwrap(text.range(of: "http"))
        XCTAssertEqual(text[http].link?.scheme, "http")
        for label in ["письмо", "путь", "хост"] {
            let word = try XCTUnwrap(text.range(of: label))
            XCTAssertNil(text[word].link)
        }
        XCTAssertEqual(markdown.preview, "веб http письмо путь хост")
    }

    func testImagesAndHTMLAreTextNotResources() throws {
        let source = "Фото ![Подпись](https://example.org/image.png) и ![](q.png) <i>видно</i>"
        let text = try paragraph(in: CardMarkdown(source: source))
        XCTAssertEqual(String(text.characters), "Фото Подпись и ![](q.png) <i>видно</i>")
        XCTAssertTrue(text.runs.allSatisfy { $0.link == nil })
        let html = "<div data-value='a'>**буквально**</div>"
        XCTAssertEqual(CardMarkdown(source: html).blocks, [.paragraph(AttributedString(html))])
    }

    func testUnsupportedBlocksAndInlinesPreserveSource() throws {
        let quote = "> одна\r\n>   **две**"
        let table = "| x | y |\n|---|---|\n| 1 | 2 |"
        for source in [quote, table, "- [x] задача", "[ref]: https://example.org"] {
            XCTAssertEqual(CardMarkdown(source: source).blocks, [.paragraph(AttributedString(source))])
        }
        let inline = "До 📝 ~~зачёркнуто~~ и $x+y$"
        XCTAssertEqual(String(try paragraph(in: CardMarkdown(source: inline)).characters), inline)
        XCTAssertTrue(CardMarkdown(source: "").blocks.isEmpty)
    }

    private func paragraph(in markdown: CardMarkdown, at index: Int = 0) throws -> AttributedString {
        let content = markdown.blocks.dropFirst(index).first.flatMap { block -> AttributedString? in
            guard case .paragraph(let text) = block else { return nil }
            return text
        }
        return try XCTUnwrap(content, "Expected a paragraph at index \(index)")
    }
}
