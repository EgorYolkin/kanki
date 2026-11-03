import XCTest

@MainActor
final class SyncStatusUITests: XCTestCase {
    func testStatusHiddenWithoutConfiguredServer() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"]
        app.launch()

        app.tabBars.buttons["Обучение"].tap()
        let status = app.staticTexts["syncStatus"]
        XCTAssertFalse(status.waitForExistence(timeout: 2), "Без настроенного сервера строки синхронизации быть не должно")

        app.buttons["addSessionCard"].tap()
        let question = app.descendants(matching: .any)["cardQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("Почему небо голубое?")
        let answer = app.descendants(matching: .any)["cardAnswer"]
        answer.tap()
        answer.typeText("Рассеивание Рэлея")
        app.buttons["Добавить"].tap()

        XCTAssertFalse(status.waitForExistence(timeout: 2), "Без настроенного сервера строка не появляется даже с несинхронизированной правкой")
    }
}
