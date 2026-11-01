import XCTest

@MainActor
final class SessionCardUITests: XCTestCase {
    func testCardIsAddedViewedAndLostAfterRestart() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["addSessionCard"].tap()
        let question = app.descendants(matching: .any)["cardQuestion"]
        let answer = app.descendants(matching: .any)["cardAnswer"]
        XCTAssertFalse(app.buttons["Добавить"].isEnabled)
        question.tap()
        question.typeText("Почему небо голубое?")
        XCTAssertFalse(app.buttons["Добавить"].isEnabled)
        answer.tap()
        answer.typeText("Рассеяние света")
        app.buttons["Добавить"].tap()

        let card = app.buttons["Почему небо голубое?"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertFalse(app.staticTexts["Рассеяние света"].exists)
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts["Рассеяние света"].exists)
        let ratingScreen = XCTAttachment(screenshot: app.screenshot())
        ratingScreen.lifetime = .keepAlways
        add(ratingScreen)
        for label in ["Снова", "Трудно", "Хорошо", "Легко"] {
            XCTAssertTrue(app.buttons[label].exists)
        }
        app.buttons["Хорошо"].tap()
        XCTAssertTrue(app.staticTexts["Оценок в этом сеансе: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Хорошо"].exists)

        card.tap()
        XCTAssertFalse(app.buttons["Снова"].exists)
        app.buttons["Показать ответ"].tap()
        app.buttons["Снова"].tap()
        XCTAssertTrue(app.staticTexts["Оценок в этом сеансе: 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Снова"].exists)

        app.terminate()
        app.launch()
        XCTAssertFalse(app.buttons["Почему небо голубое?"].exists)
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].exists)
        XCTAssertFalse(app.staticTexts["Оценок в этом сеансе: 2"].exists)
        XCTAssertFalse(app.staticTexts["Последняя оценка: Снова"].exists)
    }

    func testShellTabsAndPlaceholderNavigation() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Карточек пока нет"].exists)
        app.buttons["Будущий экран повторения"].tap()
        XCTAssertTrue(app.staticTexts["Это заготовка экрана. Данные и действия появятся на следующих этапах."].exists)
        app.navigationBars.buttons["Обучение"].tap()

        app.tabBars.buttons["Заметки"].tap()
        XCTAssertTrue(app.staticTexts["Заметок пока нет"].exists)
        for label in ["Поиск", "Экран заметки", "Редактор", "Библиотека"] {
            app.buttons[label].tap()
            XCTAssertTrue(app.staticTexts["Это заготовка экрана. Данные и действия появятся на следующих этапах."].exists)
            app.navigationBars.buttons["Заметки"].tap()
        }

        app.tabBars.buttons["Граф"].tap()
        XCTAssertTrue(app.staticTexts["Граф пуст"].exists)
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.staticTexts["Сервер не подключён"].exists)
        for label in ["Очередь мержей", "Конфликты"] {
            app.buttons[label].tap()
            XCTAssertTrue(app.staticTexts["Это заготовка экрана. Данные и действия появятся на следующих этапах."].exists)
            app.navigationBars.buttons["Настройки"].tap()
        }
    }

}
