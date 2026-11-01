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

    func testReviewSessionCoversQueueAndSummarizes() {
        let app = XCUIApplication()
        app.launch()

        addCard(in: app, question: "Что такое Km?", answer: "Концентрация при половине Vmax")
        addCard(in: app, question: "Что растёт у конкурентного ингибитора?", answer: "Растёт Km")

        app.buttons["startReviewSession"].tap()
        XCTAssertTrue(app.staticTexts["Карточка 1 из 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Концентрация при половине Vmax"].exists)
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts["Концентрация при половине Vmax"].exists)
        app.buttons["Хорошо"].tap()

        XCTAssertTrue(app.staticTexts["Карточка 2 из 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Растёт Km"].waitForExistence(timeout: 1))
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts["Растёт Km"].waitForExistence(timeout: 5))
        app.buttons["Снова"].tap()

        XCTAssertTrue(app.staticTexts["Сеанс завершён"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Оценено карточек: 2."].exists)
        XCTAssertTrue(app.staticTexts["Хорошо"].exists)
        XCTAssertTrue(app.staticTexts["Снова"].exists)
        app.buttons["reviewFinish"].tap()

        XCTAssertTrue(app.staticTexts["Оценок в этом сеансе: 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startReviewSession"].isEnabled)
    }

    private func addCard(in app: XCUIApplication, question: String, answer: String) {
        app.buttons["addSessionCard"].tap()
        let questionField = app.descendants(matching: .any)["cardQuestion"]
        let answerField = app.descendants(matching: .any)["cardAnswer"]
        questionField.tap()
        questionField.typeText(question)
        answerField.tap()
        answerField.typeText(answer)
        app.buttons["Добавить"].tap()
    }

    func testShellTabsAndPlaceholderNavigation() {
        let app = XCUIApplication()
        app.launch()

        let placeholder = app.staticTexts["Это заготовка экрана. Данные и действия появятся на следующих этапах."]
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startReviewSession"].isEnabled)
        app.tabBars.buttons["Заметки"].tap()
        let emptyNotes = app.staticTexts["Заметок пока нет"]
        XCTAssertTrue(emptyNotes.waitForExistence(timeout: 5))
        for label in ["Поиск", "Экран заметки", "Редактор", "Библиотека"] {
            let destination = app.buttons[label]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "Кнопка «\(label)» не появилась")
            destination.tap()
            XCTAssertTrue(placeholder.waitForExistence(timeout: 5), "Не открылся экран «\(label)»")
            let back = app.navigationBars.buttons["Заметки"]
            XCTAssertTrue(back.waitForExistence(timeout: 5), "Нет кнопки возврата на вкладку «Заметки»")
            back.tap()
            XCTAssertTrue(emptyNotes.waitForExistence(timeout: 5), "Не вернулись на вкладку «Заметки» после «\(label)»")
        }

        app.tabBars.buttons["Граф"].tap()
        XCTAssertTrue(app.staticTexts["Граф пуст"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.staticTexts["Сервер не подключён"].waitForExistence(timeout: 5))
        for label in ["Очередь мержей", "Конфликты"] {
            let destination = app.buttons[label]
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "Кнопка «\(label)» не появилась")
            destination.tap()
            XCTAssertTrue(placeholder.waitForExistence(timeout: 5), "Не открылся экран «\(label)»")
            let back = app.navigationBars.buttons["Настройки"]
            XCTAssertTrue(back.waitForExistence(timeout: 5), "Нет кнопки возврата на вкладку «Настройки»")
            back.tap()
            XCTAssertTrue(app.staticTexts["Сервер не подключён"].waitForExistence(timeout: 5), "Не вернулись на вкладку «Настройки»")
        }
    }

}
