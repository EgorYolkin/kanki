import XCTest

@MainActor
final class SessionCardUITests: XCTestCase {
    func testCardAndReviewsPersistAfterRestart() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Почему небо голубое?", answer: "Рассеяние света")

        let card = app.buttons["Почему небо голубое?"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertFalse(app.staticTexts["Рассеяние света"].exists)
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts["Рассеяние света"].exists)
        for label in ["Снова", "Трудно", "Хорошо", "Легко"] {
            XCTAssertTrue(app.buttons[label].exists)
        }
        let ratingScreen = XCTAttachment(screenshot: app.screenshot())
        ratingScreen.lifetime = .keepAlways
        add(ratingScreen)
        app.buttons["Хорошо"].tap()
        XCTAssertTrue(app.staticTexts["Оценок: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Хорошо"].exists)

        card.tap()
        XCTAssertFalse(app.buttons["Снова"].exists)
        app.buttons["Показать ответ"].tap()
        app.buttons["Снова"].tap()
        XCTAssertTrue(app.staticTexts["Оценок: 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Снова"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.buttons["Почему небо голубое?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Оценок: 2"].exists)
        XCTAssertTrue(app.staticTexts["Последняя оценка: Снова"].exists)
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 0")
        XCTAssertFalse(app.buttons["startReviewSession"].isEnabled)
        card.tap()
        XCTAssertTrue(app.staticTexts["История повторений"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Снова"].exists)
        XCTAssertTrue(app.staticTexts["Хорошо"].exists)
    }

    func testReviewSessionCoversQueueAndSummarizes() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Что такое Km?", answer: "Концентрация при половине Vmax")
        addCard(in: app, question: "Что растёт у конкурентного ингибитора?", answer: "Растёт Km")

        let startReview = app.buttons["startReviewSession"]
        XCTAssertEqual(app.buttons.matching(identifier: "startReviewSession").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "addSessionCard").count, 1)
        XCTAssertTrue(startReview.isEnabled)
        XCTAssertTrue(startReview.isHittable)
        let tabBar = app.tabBars.firstMatch
        XCTAssertLessThanOrEqual(startReview.frame.maxY, tabBar.frame.minY, "Кнопка перекрывает таб-бар")
        XCTAssertGreaterThan(startReview.frame.midX, app.frame.midX, "Кнопка не в правой половине экрана")
        XCTAssertEqual(startReview.frame.width, 56, accuracy: 1)
        XCTAssertEqual(startReview.frame.height, 56, accuracy: 1)

        startReview.tap()
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

        XCTAssertTrue(app.staticTexts["Оценок: 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 0")
        XCTAssertFalse(app.buttons["startReviewSession"].isEnabled)
    }

    func testEasyRatingRemovesCardFromDueQueue() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Что такое FSRS?", answer: "Планировщик повторений")
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 1")

        app.buttons["startReviewSession"].tap()
        XCTAssertTrue(app.staticTexts["Карточка 1 из 1"].waitForExistence(timeout: 5))
        app.buttons["Показать ответ"].tap()
        app.buttons["Легко"].tap()

        XCTAssertTrue(app.staticTexts["Сеанс завершён"].waitForExistence(timeout: 5))
        app.buttons["reviewFinish"].tap()

        XCTAssertTrue(app.staticTexts["dueCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 0")
        XCTAssertFalse(app.buttons["startReviewSession"].isEnabled)
        XCTAssertTrue(app.buttons["Что такое FSRS?"].exists)
    }

    func testSearchFiltersCardsByQuestion() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Почему небо голубое?", answer: "Рассеяние света")
        addCard(in: app, question: "Что такое Km?", answer: "Концентрация при половине Vmax")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("небо")

        XCTAssertTrue(app.buttons["Почему небо голубое?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Что такое Km?"].exists)
        XCTAssertFalse(app.staticTexts["Ничего не найдено"].exists)
    }

    func testShellTabsAndPlaceholderNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        let placeholder = app.staticTexts["Это заготовка экрана. Данные и действия появятся на следующих этапах."]
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "startReviewSession").count, 1)
        XCTAssertFalse(app.buttons["startReviewSession"].isEnabled)
        assertFloatingActions(in: app)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
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
        XCTAssertTrue(app.staticTexts["Не подключён"].waitForExistence(timeout: 5))
        for label in ["Очередь мержей", "Конфликты"] {
            let destination = app.buttons[label]
            scrollTo(destination, in: app)
            XCTAssertTrue(destination.waitForExistence(timeout: 5), "Кнопка «\(label)» не появилась")
            destination.tap()
            XCTAssertTrue(placeholder.waitForExistence(timeout: 5), "Не открылся экран «\(label)»")
            let back = app.navigationBars.buttons["Настройки"]
            XCTAssertTrue(back.waitForExistence(timeout: 5), "Нет кнопки возврата на вкладку «Настройки»")
            back.tap()
            XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5), "Не вернулись на вкладку «Настройки»")
        }
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    func testExportMenuSavesSelectedAndAllCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
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
        let suffix = UUID().uuidString.prefix(8)
        filename.tap()
        filename.typeText("-\(suffix)-selected")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["cardExportMenu"].waitForExistence(timeout: 5))

        app.buttons["cardExportMenu"].tap()
        app.buttons["Экспортировать все"].tap()
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        filename.tap()
        filename.typeText("-\(suffix)-all")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["cardExportMenu"].waitForExistence(timeout: 5))
    }

    /// Обе плавающие кнопки постоянно стоят в правом нижнем углу над таб-баром:
    /// повторение 56 pt под кнопкой «плюс» 44 pt, без перекрытий.
    private func assertFloatingActions(in app: XCUIApplication) {
        let add = app.buttons["addSessionCard"]
        let review = app.buttons["startReviewSession"]
        let tabBar = app.tabBars.firstMatch

        XCTAssertTrue(add.exists && review.exists, "Обе плавающие кнопки должны быть видны одновременно")
        XCTAssertEqual(add.frame.width, 44, accuracy: 1)
        XCTAssertEqual(add.frame.height, 44, accuracy: 1)
        XCTAssertEqual(review.frame.width, 56, accuracy: 1)
        XCTAssertEqual(review.frame.height, 56, accuracy: 1)
        for button in [add, review] {
            XCTAssertGreaterThan(button.frame.midX, app.frame.midX, "Кнопка должна быть в правой половине экрана")
            XCTAssertLessThanOrEqual(button.frame.maxY, tabBar.frame.minY, "Кнопка не должна перекрывать таб-бар")
        }
        XCTAssertLessThanOrEqual(add.frame.maxY, review.frame.minY, "Кнопка «плюс» должна быть над повторением")
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
}
