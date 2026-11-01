import XCTest
@testable import Kanki

final class AppSectionTests: XCTestCase {
    func testTitlesAndSymbolsAreUnique() {
        let titles = AppSection.allCases.map(\.title)
        let symbols = AppSection.allCases.map(\.symbol)

        XCTAssertEqual(Set(titles).count, titles.count, "Подписи разделов должны быть уникальны")
        XCTAssertEqual(Set(symbols).count, symbols.count, "Иконки разделов должны быть уникальны")
    }

    func testShortcutNumbersMatchTabOrder() {
        // ⌘1…⌘4 на macOS берутся из rawValue, поэтому нумерация обязана идти
        // подряд от единицы в порядке вкладок.
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), [1, 2, 3, 4])
        XCTAssertEqual(AppSection.allCases, [.learning, .notes, .graph, .settings])
    }

    func testTitles() {
        XCTAssertEqual(AppSection.learning.title, "Обучение")
        XCTAssertEqual(AppSection.notes.title, "Заметки")
        XCTAssertEqual(AppSection.graph.title, "Граф")
        XCTAssertEqual(AppSection.settings.title, "Настройки")
    }

    func testSymbols() {
        XCTAssertEqual(AppSection.learning.symbol, "rectangle.stack")
        XCTAssertEqual(AppSection.notes.symbol, "note.text")
        XCTAssertEqual(AppSection.graph.symbol, "circle.hexagongrid")
        XCTAssertEqual(AppSection.settings.symbol, "gearshape")
    }
}
