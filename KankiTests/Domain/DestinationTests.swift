import XCTest
@testable import Kanki

final class DestinationTests: XCTestCase {
    func testEveryCaseHasTitleAndSymbol() {
        let titles = Destination.allCases.map(\.title)
        let symbols = Destination.allCases.map(\.symbol)

        XCTAssertEqual(Set(titles).count, titles.count, "Заголовки экранов должны быть уникальны")
        XCTAssertEqual(Set(symbols).count, symbols.count, "Иконки экранов должны быть уникальны")
        XCTAssertFalse(titles.contains(where: \.isEmpty))
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }

    func testTitles() {
        XCTAssertEqual(Destination.note.title, "Заметка")
        XCTAssertEqual(Destination.editor.title, "Редактор заметки")
        XCTAssertEqual(Destination.search.title, "Поиск")
        XCTAssertEqual(Destination.library.title, "Библиотека")
    }

    func testSymbols() {
        XCTAssertEqual(Destination.note.symbol, "note.text")
        XCTAssertEqual(Destination.editor.symbol, "square.and.pencil")
        XCTAssertEqual(Destination.search.symbol, "magnifyingglass")
        XCTAssertEqual(Destination.library.symbol, "books.vertical")
    }
}
