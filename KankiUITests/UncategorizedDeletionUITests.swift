import XCTest

@MainActor
final class UncategorizedDeletionUITests: UITestCase {
    func testDeletingUncategorizedCardsRequiresConfirmationAndPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server", "--reset-sections"]
        app.launch()
        addCard(in: app, question: "Демо: без категории", answer: "Ответ без категории")
        addCard(in: app, question: "Демо: архив без категории", answer: "Архивный ответ")
        addCard(in: app, question: "Демо: сохранить", answer: "Сохранённый ответ", deck: .new("Демо"))

        openAllCards(in: app)
        app.buttons["Демо: без категории"].tap()
        app.buttons["Показать ответ"].tap()
        app.buttons["Хорошо"].tap()
        let archivedCard = app.buttons["Демо: архив без категории"]
        XCTAssertTrue(archivedCard.waitForExistence(timeout: 5))
        archivedCard.swipeRight()
        app.buttons["archiveCardSwipe"].tap()
        backToLearning(in: app)

        let uncategorized = categoryRow(in: app, named: "Без категории")
        scrollTo(uncategorized, in: app)
        XCTAssertTrue(uncategorized.isHittable)
        uncategorized.swipeLeft()
        app.buttons["deleteUncategorizedCards"].tap()
        let confirmation = app.alerts["Удалить карточки без категории?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "2, включая архивные")
        ).firstMatch.exists)
        attach(app, name: "Удаление без категории — подтверждение количества")
        confirmation.buttons["Отмена"].tap()
        XCTAssertTrue(uncategorized.waitForExistence(timeout: 5))

        openAllCards(in: app)
        XCTAssertTrue(app.buttons["Демо: без категории"].waitForExistence(timeout: 5))
        app.buttons["archiveFilterChip"].tap()
        XCTAssertTrue(app.buttons["Демо: архив без категории"].waitForExistence(timeout: 5))
        backToLearning(in: app)
        scrollTo(uncategorized, in: app)
        uncategorized.press(forDuration: 1.2)
        app.buttons["deleteUncategorizedCards"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Удалить"].tap()
        XCTAssertFalse(uncategorized.exists)
        XCTAssertTrue(app.staticTexts["Оценок: 0"].waitForExistence(timeout: 5))
        attach(app, name: "После удаления — именованная категория сохранена")

        app.terminate()
        app.launchArguments = ["--reset-server", "--reset-sections"]
        app.launch()
        XCTAssertTrue(app.buttons["Все карточки"].waitForExistence(timeout: 5))
        XCTAssertFalse(categoryRow(in: app, named: "Без категории").exists)
        openAllCards(in: app)
        XCTAssertTrue(app.buttons["Демо: сохранить"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Демо: без категории"].exists)
        XCTAssertFalse(app.buttons["Демо: архив без категории"].exists)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
