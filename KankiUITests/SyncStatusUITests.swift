import XCTest

@testable import Kanki

@MainActor
final class SyncStatusUITests: XCTestCase {
    func testStatusHiddenWithoutConfiguredServer() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
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

    /// Недоступный сервер честно показывается и в настройках, и на «Обучении»:
    /// `127.0.0.1:9` даёт реальный отказ соединения без моков.
    func testUnreachableServerShowsHonestStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        // Строка статуса живёт в блоке статистики, который есть только при
        // хотя бы одной карточке.
        app.buttons["addSessionCard"].tap()
        let question = app.descendants(matching: .any)["cardQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("Почему небо голубое?")
        let answer = app.descendants(matching: .any)["cardAnswer"]
        answer.tap()
        answer.typeText("Рассеивание Рэлея")
        app.buttons["Добавить"].tap()

        app.tabBars.buttons["Настройки"].tap()
        let serverURL = app.textFields["serverURL"]
        XCTAssertTrue(serverURL.waitForExistence(timeout: 10))
        serverURL.tap()
        serverURL.typeText("http://127.0.0.1:9")
        let serverToken = app.secureTextFields["serverToken"]
        serverToken.tap()
        serverToken.typeText("offline-token")
        app.buttons["serverCheck"].tap()

        let serverStatus = app.staticTexts["serverStatus"]
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Не удалось связаться"),
            evaluatedWith: serverStatus
        )
        waitForExpectations(timeout: 30)

        // Перезапуск без сброса: токен и адрес сохранены, при старте идёт
        // сверка и «Обучение» должно показать причину, а не «всё синхронизировано».
        app.launchArguments = []
        app.terminate()
        app.launch()

        let syncStatus = app.staticTexts["syncStatus"]
        XCTAssertTrue(syncStatus.waitForExistence(timeout: 30))
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Сервер недоступен"),
            evaluatedWith: syncStatus
        )
        waitForExpectations(timeout: 30)
    }
}
