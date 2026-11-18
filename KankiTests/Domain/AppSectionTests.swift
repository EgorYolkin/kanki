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
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), [1, 2, 3, 4, 5])
        XCTAssertEqual(AppSection.allCases, [.learning, .notes, .graph, .settings, .statistics])
    }

    func testVisibleSectionsHidePlaceholderTabsByDefault() {
        XCTAssertEqual(AppSection.visible(notesShown: false, graphShown: false),
                       [.learning, .settings, .statistics])
        XCTAssertEqual(AppSection.visible(notesShown: true, graphShown: true),
                       [.learning, .notes, .graph, .settings, .statistics])
        XCTAssertEqual(AppSection.visible(notesShown: false, graphShown: true),
                       [.learning, .graph, .settings, .statistics])
        XCTAssertEqual(AppSection.visible(notesShown: true, graphShown: false),
                       [.learning, .notes, .settings, .statistics])
    }

    func testTitles() {
        XCTAssertEqual(AppSection.learning.title, "Обучение")
        XCTAssertEqual(AppSection.notes.title, "Заметки")
        XCTAssertEqual(AppSection.graph.title, "Граф")
        XCTAssertEqual(AppSection.settings.title, "Настройки")
        XCTAssertEqual(AppSection.statistics.title, "Статистика")
    }

    func testSymbols() {
        XCTAssertEqual(AppSection.learning.symbol, "rectangle.stack")
        XCTAssertEqual(AppSection.notes.symbol, "note.text")
        XCTAssertEqual(AppSection.graph.symbol, "circle.hexagongrid")
        XCTAssertEqual(AppSection.settings.symbol, "gearshape")
        XCTAssertEqual(AppSection.statistics.symbol, "chart.bar")
    }
}
