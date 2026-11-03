import XCTest

/// Свайпы по карточкам в списке «Все карточки»: влево — удаление,
/// вправо — архив; архивные карточки видны под чипом «Архив».
@MainActor
final class CardArchiveUITests: UITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()
        return app
    }

    func testSwipeRightArchivesCardAndRestoresIt() {
        let app = launch()
        addCard(in: app, question: "Архивируемая карточка", answer: "Ответ")
        addCard(in: app, question: "Обычная карточка", answer: "Ответ")

        openAllCards(in: app)
        let card = app.buttons["Архивируемая карточка"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.swipeRight()
        let archive = app.buttons["В архив"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5), "Нет действия «В архив» на свайпе вправо")
        archive.tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2), "Архивная карточка осталась в основном списке")
        XCTAssertTrue(app.buttons["Обычная карточка"].exists)

        let archiveChip = app.buttons["archiveFilterChip"]
        XCTAssertTrue(archiveChip.waitForExistence(timeout: 5), "Нет чипа «Архив»")
        archiveChip.tap()

        let archivedCard = app.buttons["Архивируемая карточка"]
        XCTAssertTrue(archivedCard.waitForExistence(timeout: 5), "Карточка не появилась в архиве")
        XCTAssertTrue(app.staticTexts["В архиве"].exists, "Нет подписи «В архиве»")

        archivedCard.swipeRight()
        let restore = app.buttons["Вернуть"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "Нет действия «Вернуть»")
        restore.tap()
        XCTAssertFalse(archivedCard.waitForExistence(timeout: 2), "Карточка осталась в архиве")

        archiveChip.tap()
        XCTAssertTrue(app.buttons["Архивируемая карточка"].waitForExistence(timeout: 5))
    }

    func testSwipeLeftDeletesCardOnlyAfterConfirmation() {
        let app = launch()
        addCard(in: app, question: "Удаляемая карточка", answer: "Ответ")
        addCard(in: app, question: "Оставшаяся карточка", answer: "Ответ")

        openAllCards(in: app)
        let card = app.buttons["Удаляемая карточка"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.swipeLeft()
        let delete = app.buttons["Удалить"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Нет действия «Удалить» на свайпе влево")
        delete.tap()

        let alert = app.alerts["Удалить карточку и историю повторений?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Удаление без подтверждения")
        alert.buttons["Отмена"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Карточка удалена без подтверждения")

        card.swipeLeft()
        app.buttons["Удалить"].tap()
        alert.buttons["Удалить карточку"].tap()

        XCTAssertFalse(card.waitForExistence(timeout: 2), "Карточка не удалена")
        XCTAssertTrue(app.buttons["Оставшаяся карточка"].exists)
    }
}
