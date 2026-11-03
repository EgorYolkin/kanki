import XCTest

@MainActor
final class SessionCardUITests: UITestCase {
    func testCardAndReviewsPersistAfterRestart() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Почему небо голубое?", answer: "Рассеяние света")

        openAllCards(in: app)
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

        backToLearning(in: app)
        XCTAssertTrue(app.staticTexts["Оценок: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Хорошо"].exists)

        openAllCards(in: app)
        app.buttons["Почему небо голубое?"].tap()
        XCTAssertFalse(app.buttons["Снова"].exists)
        app.buttons["Показать ответ"].tap()
        app.buttons["Снова"].tap()

        backToLearning(in: app)
        XCTAssertTrue(app.staticTexts["Оценок: 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Снова"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.staticTexts["Оценок: 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последняя оценка: Снова"].exists)
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 0")
        XCTAssertFalse(app.buttons["startReviewSession"].isEnabled)

        openAllCards(in: app)
        XCTAssertTrue(app.buttons["Почему небо голубое?"].waitForExistence(timeout: 5))
        app.buttons["Почему небо голубое?"].tap()
        XCTAssertTrue(app.staticTexts["История повторений"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Снова"].exists)
        XCTAssertTrue(app.staticTexts["Хорошо"].exists)
    }

    func testDeletingCardRequiresConfirmationAndPersistsWithoutOtherCardHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()
        addCard(in: app, question: "Удаляемая карточка", answer: "Ответ А")
        addCard(in: app, question: "Оставшаяся карточка", answer: "Ответ Б")

        openAllCards(in: app)
        app.buttons["Оставшаяся карточка"].tap()
        app.buttons["Показать ответ"].tap()
        app.buttons["Хорошо"].tap()
        backToLearning(in: app)
        XCTAssertTrue(app.staticTexts["Оценок: 1"].waitForExistence(timeout: 5))

        openAllCards(in: app)
        app.buttons["Удаляемая карточка"].tap()
        app.buttons["deleteSessionCard"].tap()
        let confirmation = app.alerts["Удалить карточку и историю повторений?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Отмена"].tap()
        XCTAssertTrue(app.navigationBars["Карточка"].exists)
        app.buttons["deleteSessionCard"].tap()
        app.alerts["Удалить карточку и историю повторений?"].buttons["Удалить карточку"].tap()

        XCTAssertFalse(app.buttons["Удаляемая карточка"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Оставшаяся карточка"].exists)

        backToLearning(in: app)
        XCTAssertTrue(app.staticTexts["Оценок: 1"].exists)
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 0")

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Оценок: 1"].waitForExistence(timeout: 5))

        openAllCards(in: app)
        XCTAssertFalse(app.buttons["Удаляемая карточка"].exists)
        XCTAssertTrue(app.buttons["Оставшаяся карточка"].waitForExistence(timeout: 5))
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
        XCTAssertEqual(startReview.label, "Начать повторение")
        let tabBar = app.tabBars.firstMatch
        XCTAssertLessThanOrEqual(startReview.frame.maxY, tabBar.frame.minY, "Кнопка перекрывает таб-бар")
        XCTAssertGreaterThan(startReview.frame.minX, app.frame.midX, "Кнопка повторения стоит справа")
        XCTAssertGreaterThan(startReview.frame.width, 48, "Плавающая кнопка остаётся нажимаемой")
        XCTAssertEqual(app.staticTexts["newCount"].label, "Новых: 2")

        startReview.tap()
        XCTAssertTrue(app.staticTexts["Карточка 1 из 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reviewDeck"].label, "Без категории")
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

        openAllCards(in: app)
        XCTAssertTrue(app.buttons["Что такое FSRS?"].exists)
    }

    func testSearchFiltersCardsByQuestion() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Почему небо голубое?", answer: "Рассеяние света")
        addCard(in: app, question: "Что такое Km?", answer: "Концентрация при половине Vmax")

        openAllCards(in: app)
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
        XCTAssertEqual(app.searchFields.count, 0)
        XCTAssertFalse(app.buttons["Все карточки"].exists)
        assertAddButton(in: app)

        addCard(in: app, question: "Проверка оболочки", answer: "Ответ")
        XCTAssertFalse(app.searchFields.firstMatch.exists, "Поиска на главном экране больше нет")
        XCTAssertFalse(app.buttons["Проверка оболочки"].exists, "Список карточек переехал в «Все карточки»")
        let allCards = app.buttons["Все карточки"]
        XCTAssertTrue(allCards.waitForExistence(timeout: 5))
        allCards.tap()
        XCTAssertTrue(app.navigationBars["Все карточки"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.buttons["Проверка оболочки"].exists)
        backToLearning(in: app)

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

        let merges = app.buttons["Очередь мержей"]
        scrollTo(merges, in: app)
        XCTAssertTrue(merges.waitForExistence(timeout: 5), "Кнопка «Очередь мержей» не появилась")
        merges.tap()
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5), "Не открылся экран «Очередь мержей»")
        app.navigationBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))

        let conflicts = app.buttons["Конфликты"]
        scrollTo(conflicts, in: app)
        XCTAssertTrue(conflicts.waitForExistence(timeout: 5), "Кнопка «Конфликты» не появилась")
        conflicts.tap()
        XCTAssertTrue(app.staticTexts["Конфликтов нет"].waitForExistence(timeout: 5), "Экран «Конфликты» больше не заглушка")
        app.navigationBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
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

    func testEditingCardUpdatesQuestionAnswerAndCategory() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        addCard(in: app, question: "Старый вопрос", answer: "Старый ответ", deck: .new("Математика"))
        openAllCards(in: app)
        app.buttons["Старый вопрос"].tap()

        let edit = app.buttons["editSessionCard"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Нет кнопки «Изменить» на карточке")
        edit.tap()

        let questionField = app.descendants(matching: .any)["cardQuestion"]
        XCTAssertTrue(questionField.waitForExistence(timeout: 5), "Форма редактирования не открылась")
        XCTAssertEqual(questionField.value as? String, "Старый вопрос", "Форма не заполнена текущим вопросом")
        replaceText(in: questionField, with: "Новый вопрос")
        replaceText(in: app.descendants(matching: .any)["cardAnswer"], with: "Новый ответ")

        let save = app.buttons["Сохранить"]
        XCTAssertTrue(save.isEnabled, "Кнопка «Сохранить» заблокирована")
        save.tap()

        // После сохранения форма закрывается, а карточка остаётся открытой с новыми данными.
        XCTAssertFalse(save.waitForExistence(timeout: 2), "Форма редактирования не закрылась")
        XCTAssertTrue(app.staticTexts["Новый вопрос"].waitForExistence(timeout: 5), "Карточка не обновилась")
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts["Новый ответ"].waitForExistence(timeout: 5), "Ответ не сохранился")
        XCTAssertTrue(app.staticTexts["Математика"].exists, "Категория потерялась при правке")

        app.buttons["Закрыть"].tap()
        XCTAssertTrue(app.buttons["Новый вопрос"].waitForExistence(timeout: 5), "Список не обновился")
        XCTAssertFalse(app.buttons["Старый вопрос"].exists, "Старый вопрос остался в списке")
    }

    /// Заменяет текст поля новым значением и проверяет результат.
    private func replaceText(in field: XCUIElement, with text: String) {
        // Тап по центру ставит курсор в начало, поэтому удаление ничего не стирает:
        // ставим курсор в конец поля и удаляем с запасом.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "Поле содержит «\(field.value ?? "")» вместо «\(text)»")
    }
}
