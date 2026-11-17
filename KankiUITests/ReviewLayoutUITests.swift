import XCTest

@MainActor
final class ReviewLayoutUITests: UITestCase {
    func testLongAnswerKeepsAllRatingsVisibleAndNextQuestionStartsAtTop() {
        exerciseLongReview(appearance: "light")
    }

    func testLongAnswerKeepsAllRatingsVisibleWithAccessibilityText() {
        exerciseLongReview(appearance: "dark", accessibilityText: true)
    }

    private func exerciseLongReview(appearance: String, accessibilityText: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server", "--reset-sections", "-appearance", appearance]
        app.launch()

        let question = "Демо: как проверить удобство длинной карточки?"
        let paragraph = "Демо. Длинный ответ прокручивается отдельно от действий. Все четыре оценки остаются доступны. "
        let answer = String(repeating: paragraph, count: 12) + "Конец демо-ответа."
        addCard(in: app, question: question, answer: answer)
        addCard(in: app, question: "Демо: следующий вопрос", answer: "Следующий ответ скрыт до раскрытия.")
        if accessibilityText {
            app.terminate()
            app.launchArguments = [
                "-appearance", appearance,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()
        }

        let start = app.buttons["startReviewSession"]
        scrollTo(start, in: app)
        start.tap()
        XCTAssertTrue(app.staticTexts["reviewProgress"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@", answer)).firstMatch.exists)
        let reveal = app.buttons["Показать ответ"]
        XCTAssertTrue(reveal.isHittable, "Раскрытие ответа доступно без прокрутки вопроса")
        reveal.tap()
        assertRatingsVisible(in: app)
        attachScreen(app, name: "Длинная карточка — \(appearance)\(accessibilityText ? " — крупный текст" : "")")

        let content = app.scrollViews.firstMatch
        XCTAssertTrue(content.exists)
        content.swipeUp()
        content.swipeUp()
        assertRatingsVisible(in: app)
        app.buttons["Хорошо"].tap()

        XCTAssertTrue(app.staticTexts["Демо: следующий вопрос"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Демо: следующий вопрос"].isHittable, "Новая карточка открывается с начала")
        XCTAssertFalse(app.staticTexts["Следующий ответ скрыт до раскрытия."].exists)
        XCTAssertTrue(app.buttons["Показать ответ"].isHittable)
        app.buttons["Показать ответ"].tap()
        app.buttons["Легко"].tap()
        XCTAssertTrue(app.staticTexts["Сеанс завершён"].waitForExistence(timeout: 5))
    }

    private func assertRatingsVisible(in app: XCUIApplication) {
        let ratings = ["Снова", "Трудно", "Хорошо", "Легко"].map { app.buttons[$0] }
        for button in ratings {
            XCTAssertTrue(button.isHittable, "Оценка \(button.label) доступна без прокрутки ответа")
            XCTAssertTrue(app.frame.contains(button.frame), "Оценка \(button.label) целиком внутри экрана")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "Область нажатия не меньше 44 pt")
        }
        for (index, button) in ratings.enumerated() {
            for other in ratings.dropFirst(index + 1) {
                XCTAssertFalse(button.frame.intersects(other.frame), "Области нажатия оценок не перекрываются")
            }
        }
    }

    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
