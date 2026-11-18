import XCTest

@MainActor
final class LessonUITests: UITestCase {
    private let introduction = "Введение"
    private let plainQuestion = "Первый вопрос"
    private let markdownAnswer = "## Разбор\n\n- **Пример**\n- [Справка](https://example.org/demo)\n\n```\n**raw**\\n\n```"

    func testSameTitleInTwoCoursesAndStandaloneLessonSurviveRestart() {
        let app = launchClean()
        createLesson(in: app, title: introduction, newCourse: "Swift")
        backFromLesson(in: app)
        createLesson(in: app, title: introduction, newCourse: "Python")
        backFromLesson(in: app)
        createLesson(in: app, title: "Демо без курса")
        backFromLesson(in: app)

        restart(app)
        XCTAssertEqual(app.buttons["lessonLatest"].label, "Демо без курса · Без курса")
        XCTAssertEqual(app.staticTexts["lessonActiveCount"].label, "Активных карточек: 0")
        XCTAssertFalse(app.buttons["lessonReview"].isEnabled)
        app.buttons["lessonCatalog"].tap()
        for course in ["Swift", "Python", "Без курса"] {
            XCTAssertTrue(app.buttons[course].waitForExistence(timeout: 5))
        }
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        search.tap()
        search.typeText("введение")
        XCTAssertTrue(app.buttons["Введение · Swift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Введение · Python"].exists)
        let clear = search.buttons.firstMatch
        clear.tap()
        search.typeText("sWiFt")
        XCTAssertFalse(app.buttons["Введение · Python"].exists)
        app.buttons["Введение · Swift"].tap()
        app.buttons["lessonAddCard"].tap()
        enterCardText(in: app, question: "Только в Swift", answer: "Ответ Swift")
        app.buttons["cardDone"].tap()
        XCTAssertTrue(app.buttons["Только в Swift"].waitForExistence(timeout: 5))

        restart(app)
        XCTAssertEqual(app.buttons["lessonLatest"].label, "Демо без курса · Без курса")
        app.buttons["lessonCatalog"].tap()
        app.buttons["Python"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", introduction)).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["В этом уроке пока нечего повторять"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Только в Swift"].exists)
    }

    func testBatchAndLessonReviewIncludeFutureAndNewButNotArchivedOrOutside() {
        let app = launchClean()
        addCard(in: app, question: "Посторонняя карточка", answer: "Демо", deck: .new("Тема"))
        createLesson(in: app, title: introduction, newCourse: "Swift")
        addLessonBatch(in: app)
        XCTAssertEqual(app.staticTexts["lessonActiveCount"].label, "Активных карточек: 3")

        // Планируем первую карточку заранее, среднюю архивируем через общий список.
        app.buttons[plainQuestion].tap()
        assertMarkdownAnswer(in: app)
        app.buttons["Легко"].tap()
        XCTAssertTrue(app.buttons["lessonAddCard"].waitForExistence(timeout: 5))
        backFromLesson(in: app)
        openAllCards(in: app)
        app.buttons["Середина"].swipeRight()
        app.buttons["В архив"].tap()
        backToLearning(in: app)
        restart(app)
        XCTAssertEqual(app.buttons["lessonLatest"].label, "Введение · Swift")
        XCTAssertEqual(app.staticTexts["lessonActiveCount"].label, "Активных карточек: 2")
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 2")
        app.buttons["lessonLatest"].tap()
        let archived = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Середина", "В архиве"))
        XCTAssertTrue(archived.firstMatch.waitForExistence(timeout: 5))
        backFromLesson(in: app)

        app.buttons["lessonReview"].tap()
        XCTAssertTrue(app.navigationBars[introduction].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reviewProgress"].label, "Карточка 1 из 2")
        XCTAssertEqual(app.staticTexts["reviewDeck"].label, "Тема")
        XCTAssertTrue(app.staticTexts[plainQuestion].exists)
        assertMarkdownAnswer(in: app)
        app.buttons["Хорошо"].tap()
        XCTAssertTrue(app.staticTexts["Последний вопрос"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reviewProgress"].label, "Карточка 2 из 2")
        XCTAssertEqual(app.staticTexts["reviewDeck"].label, "Тема")
        app.buttons["Показать ответ"].tap()
        app.buttons["Легко"].tap()
        XCTAssertTrue(app.staticTexts["Оценено карточек: 2."].waitForExistence(timeout: 5))
        app.buttons["reviewFinish"].tap()
        XCTAssertTrue(app.staticTexts["Оценок: 3"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dueCount"].label, "К повторению: 1")
        openAllCards(in: app)
        let scheduled = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Следующий показ:"))
        XCTAssertEqual(scheduled.count, 2, "Обе карточки урока должны получить общий срок FSRS")
    }

    func testDuplicateLessonOpensExistingAndDeletingItKeepsTheCard() {
        let app = launchClean()
        createLesson(in: app, title: introduction, newCourse: "Swift")
        app.buttons["lessonAddCard"].tap()
        enterCardText(in: app, question: "Демо карточка", answer: "Демо ответ")
        app.buttons["cardDone"].tap()
        app.buttons["Демо карточка"].tap()
        app.buttons["Показать ответ"].tap()
        app.buttons["Хорошо"].tap()
        backFromLesson(in: app)

        chooseAddAction("Новый урок", in: app)
        app.descendants(matching: .any)["lessonCourse"].tap()
        app.buttons["Swift"].tap()
        type(" Введение ", in: app.textFields["lessonTitle"])
        let open = app.buttons["lessonOpenExisting"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["Демо карточка"].waitForExistence(timeout: 5))
        app.buttons["lessonEdit"].tap()
        type("https://example.org/demo", in: app.textFields["lessonURL"])
        app.buttons["lessonSave"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Открыть видео"].waitForExistence(timeout: 5))
        let delete = app.buttons["lessonDelete"]
        scrollTo(delete, in: app)
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Карточки и оценки останутся")).firstMatch.exists)
        alert.buttons["Удалить урок"].tap()
        XCTAssertTrue(app.buttons["lessonCreate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lessonLatest"].exists)
        openAllCards(in: app)
        app.buttons["Демо карточка"].tap()
        XCTAssertTrue(app.staticTexts["Хорошо"].waitForExistence(timeout: 5))
    }

    func testCancellingInvalidLessonLeavesNoRecord() {
        let app = launchClean()
        app.buttons["lessonCreate"].tap()
        type("Проверка ссылки", in: app.textFields["lessonTitle"])
        type("video/sample", in: app.textFields["lessonURL"])
        XCTAssertFalse(app.buttons["lessonSave"].isEnabled)
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.buttons["lessonCreate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lessonLatest"].exists)
    }

    private func addLessonBatch(in app: XCUIApplication) {
        app.buttons["lessonAddCard"].tap()
        chooseDeck(in: app, option: "Тема")
        let saveAndAdd = app.buttons["cardSaveAndAdd"]
        for (question, answer) in [("**\(plainQuestion)**", markdownAnswer), ("Середина", "Архив"), ("Последний вопрос", "Ответ")] {
            enterCardText(in: app, question: question, answer: answer)
            XCTAssertEqual(app.textViews["cardAnswer"].value as? String, answer, "Return должен вводить LF в редакторе")
            scrollTo(saveAndAdd, in: app)
            saveAndAdd.tap()
            XCTAssertFalse(saveAndAdd.isEnabled)
            XCTAssertNotEqual((app.textViews["cardQuestion"].value as? String)?.isEmpty, false)
            XCTAssertNotEqual((app.textViews["cardAnswer"].value as? String)?.isEmpty, false)
        }
        app.buttons["cardDone"].tap()
        XCTAssertTrue(app.buttons[plainQuestion].waitForExistence(timeout: 5))
    }

    private func assertMarkdownAnswer(in app: XCUIApplication) {
        let heading = app.staticTexts["Разбор"]
        XCTAssertFalse(heading.exists, "Ответ не должен попадать в дерево доступности до раскрытия")
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Пример"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Справка"].exists)
        let code = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", #"**raw**\n"#)).firstMatch
        scrollTo(code, in: app)
        XCTAssertTrue(code.exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Демо Markdown в уроке iOS"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func createLesson(in app: XCUIApplication, title: String, newCourse: String? = nil) {
        chooseAddAction("Новый урок", in: app)
        let save = app.buttons["lessonSave"]
        XCTAssertFalse(save.isEnabled)
        if let newCourse {
            app.descendants(matching: .any)["lessonCourse"].tap()
            app.buttons["Новый курс…"].tap()
            type(newCourse, in: app.textFields["lessonNewCourse"])
        }
        type(title, in: app.textFields["lessonTitle"])
        save.tap()
        XCTAssertTrue(app.buttons["lessonAddCard"].waitForExistence(timeout: 5))
    }

    private func backFromLesson(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Обучение"].waitForExistence(timeout: 5))
    }

    private func type(_ text: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    private func launchClean() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        return app
    }

    private func restart(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["lessonLatest"].waitForExistence(timeout: 5))
    }
}
