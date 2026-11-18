import XCTest

@MainActor
final class UncategorizedLibraryUITests: UITestCase {
    func testUncategorizedFilterIsDistinctFromAllAndNamedCategory() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server", "--reset-sections"]
        app.launch()

        let uncategorizedQuestion = "Демо: без категории"
        let namedQuestion = "Демо: с категорией"
        addCard(in: app, question: uncategorizedQuestion, answer: "Демонстрационный ответ без категории")
        addCard(
            in: app,
            question: namedQuestion,
            answer: "Демонстрационный ответ в категории",
            deck: .new("Демо")
        )

        openAllCards(in: app)
        let uncategorizedCard = app.buttons[uncategorizedQuestion]
        let namedCard = app.buttons[namedQuestion]
        XCTAssertTrue(uncategorizedCard.waitForExistence(timeout: 5), "«Все» скрывает карточку без категории")
        scrollTo(uncategorizedCard, in: app)
        XCTAssertTrue(uncategorizedCard.isHittable)
        XCTAssertTrue(namedCard.waitForExistence(timeout: 5), "«Все» скрывает карточку именованной категории")
        scrollTo(namedCard, in: app)
        XCTAssertTrue(namedCard.isHittable)

        let uncategorizedFilter = app.buttons["Фильтр: Без категории"]
        XCTAssertTrue(uncategorizedFilter.waitForExistence(timeout: 5))
        uncategorizedFilter.tap()
        XCTAssertTrue(uncategorizedCard.waitForExistence(timeout: 5))
        XCTAssertTrue(uncategorizedCard.isHittable)
        XCTAssertFalse(namedCard.exists, "«Без категории» не убрал карточку именованной категории")

        let namedFilter = app.buttons["Фильтр: Демо"]
        XCTAssertTrue(namedFilter.waitForExistence(timeout: 5))
        namedFilter.tap()
        XCTAssertTrue(namedCard.waitForExistence(timeout: 5))
        XCTAssertTrue(namedCard.isHittable)
        XCTAssertFalse(uncategorizedCard.exists, "Именованная категория не убрала карточку без категории")

        app.buttons["Фильтр: Все"].tap()
        XCTAssertTrue(uncategorizedCard.waitForExistence(timeout: 5), "Возврат к «Все» не восстановил карточку без категории")
        scrollTo(uncategorizedCard, in: app)
        XCTAssertTrue(uncategorizedCard.isHittable)
        XCTAssertTrue(namedCard.waitForExistence(timeout: 5))
        scrollTo(namedCard, in: app)
        XCTAssertTrue(namedCard.isHittable)
    }
}
