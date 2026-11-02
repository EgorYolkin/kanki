import XCTest

@MainActor
final class CategoryUITests: UITestCase {
    /// Создание категории через пикер карточки: строка категории на «Обучении»,
    /// фильтр по чипу и чип категории на самой карточке.
    func testCreatingCardWithNewCategoryShowsChipAndFiltersAllCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Что такое предел?", answer: "Значение, к которому стремится", deck: .new("Математика"))
        addCard(in: app, question: "Что такое Km?", answer: "Константа Михаэлиса", deck: .existing("Математика"))
        addCard(in: app, question: "Почему небо голубое?", answer: "Рассеяние света")

        let category = categoryRow(in: app, named: "Математика")
        XCTAssertTrue(category.waitForExistence(timeout: 5), "Категория не появилась на экране «Обучение»")
        XCTAssertTrue(category.label.contains("2"), "Счётчик категории должен быть 2, получено «\(category.label)»")

        openAllCards(in: app)
        XCTAssertTrue(app.buttons["Фильтр: Все"].waitForExistence(timeout: 5))
        let deckFilter = app.buttons["Фильтр: Математика"]
        XCTAssertTrue(deckFilter.waitForExistence(timeout: 5), "Нет чипа-фильтра категории")
        XCTAssertTrue(app.buttons["Почему небо голубое?"].exists)

        deckFilter.tap()
        XCTAssertTrue(app.buttons["Что такое предел?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Что такое Km?"].exists)
        XCTAssertFalse(app.buttons["Почему небо голубое?"].exists, "Фильтр не убрал карточку другой категории")

        app.buttons["Что такое предел?"].tap()
        let chip = deckChip(in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Математика")
    }

    /// Переименование категории из контекстного меню строки обновляет строку,
    /// чип-фильтр и чип открытой карточки.
    func testRenamingCategoryUpdatesRowChipAndFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Что такое предел?", answer: "Значение, к которому стремится", deck: .new("Математика"))

        renameCategory(in: app, from: "Математика", to: "Алгебра")
        XCTAssertTrue(categoryRow(in: app, named: "Алгебра").waitForExistence(timeout: 5), "Строка не переименовалась")
        XCTAssertFalse(categoryRow(in: app, named: "Математика").exists)

        openAllCards(in: app)
        XCTAssertTrue(app.buttons["Фильтр: Алгебра"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Фильтр: Математика"].exists)

        app.buttons["Что такое предел?"].tap()
        let chip = deckChip(in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Алгебра")
    }
}
