import XCTest

@MainActor
final class SessionCardUITests: XCTestCase {
    func testCardAndItsReviewHistorySurviveRestart() {
        let app = isolatedApp()
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
        XCTAssertTrue(app.staticTexts["Всего оценок: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Хорошо"].exists)

        card.tap()
        XCTAssertFalse(app.buttons["Снова"].exists)
        app.buttons["Показать ответ"].tap()
        app.buttons["Снова"].tap()
        XCTAssertTrue(app.staticTexts["Всего оценок: 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Снова"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Почему небо голубое?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Всего оценок: 2"].exists)
        card.tap()
        XCTAssertTrue(app.staticTexts["История повторений"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Снова"].exists)
        XCTAssertTrue(app.staticTexts["Хорошо"].exists)
    }

    func testReviewSessionCoversQueueAndSummarizes() {
        let app = isolatedApp()
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

        XCTAssertTrue(app.staticTexts["Всего оценок: 2"].waitForExistence(timeout: 5))
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

    func testExportMenuOpensSelectedAndAllFileDialogs() {
        let app = isolatedApp()
        app.launch()
        addCard(in: app, question: "Экспорт Альфа", answer: "Ответ А")
        addCard(in: app, question: "Экспорт Бета", answer: "Ответ Б")

        app.buttons["cardExportMenu"].tap()
        app.buttons["Выбрать карточки"].tap()
        XCTAssertTrue(app.navigationBars["Выбор карточек"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exportSelectedCards"].isEnabled)
        app.staticTexts["Экспорт Альфа"].firstMatch.tap()
        XCTAssertTrue(app.buttons["exportSelectedCards"].isEnabled)
        app.buttons["exportSelectedCards"].tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        let uniqueName = UUID().uuidString.prefix(8)
        filename.tap()
        filename.typeText("-\(uniqueName)-selected")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["cardExportMenu"].waitForExistence(timeout: 5))

        app.buttons["cardExportMenu"].tap()
        app.buttons["Экспортировать все"].tap()
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        filename.tap()
        filename.typeText("-\(uniqueName)-all")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["cardExportMenu"].waitForExistence(timeout: 5))
    }

    func testShellTabsAndPlaceholderNavigation() {
        let app = isolatedApp()
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

    private func isolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KANKI_CARD_LIBRARY_TEST_ID"] = UUID().uuidString
        return app
    }
}
