import Foundation
import XCTest

@MainActor
final class SyncStatusUITests: XCTestCase {
    func testStatusHiddenWithoutConfiguredServer() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        app.tabBars.buttons["Обучение"].tap()
        let status = app.staticTexts["syncStatus"]
        XCTAssertFalse(status.waitForExistence(timeout: 2), "Без настроенного сервера строки синхронизации быть не должно")

        addCard(in: app)

        XCTAssertFalse(status.waitForExistence(timeout: 2), "Без настроенного сервера строка не появляется даже с несинхронизированной правкой")
    }

    func testUnreachableServerShowsStatusWithNoCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        // Порт 9 на loopback не слушается: реальный отказ соединения.
        configureServer(in: app, url: "http://127.0.0.1:9", token: "offline-token", expected: "Не удалось связаться")
        restart(app)

        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        assertLabel("Сервер недоступен — повтор при следующем открытии", on: app.staticTexts["syncStatus"])
        attachScreenshot("Пустое обучение — сервер недоступен", in: app)
    }

    func testRejectedTokenOnAutoFetchAndPushIsNotConflict() throws {
        let url = try localServerURL()
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        let expected = "Токен отклонён — проверьте настройки сервера"
        configureServer(in: app, url: url, token: "synthetic-invalid-token", expected: "Токен отклонён")
        restart(app)

        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        assertLabel(expected, on: app.staticTexts["syncStatus"])
        attachScreenshot("Пустое обучение — токен отклонён", in: app)

        addCard(in: app)
        let alert = app.alerts["Синхронизация"]
        XCTAssertTrue(alert.staticTexts[expected].waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        assertLabel(expected, on: app.staticTexts["syncStatus"])
    }

    func testConflictSurvivesAlertDismissalAndClearsAfterPull() async throws {
        let url = try localServerURL()
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["KANKI_STATUS_UI_TOKEN"])
        let revision = try await advanceServerRevision(url: url, token: token)
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        configureServer(in: app, url: url, token: token, expected: "Подключено:")
        restart(app)
        let status = app.staticTexts["syncStatus"]
        assertLabel("Синхронизировано, ревизия \(revision)", on: status)

        let remoteRevision = try await advanceServerRevision(url: url, token: token)
        addCard(in: app)
        let alert = app.alerts["Синхронизация"]
        XCTAssertTrue(alert.buttons["OK"].waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        assertLabel("Конфликт ревизий — разрешите в настройках", on: status)

        app.tabBars.buttons["Настройки"].tap()
        let pull = app.buttons["serverPull"]
        if !pull.isHittable { app.swipeUp() }
        pull.tap()
        app.buttons["Заменить"].tap()
        assertLabel("Загружено, ревизия \(remoteRevision)", on: app.staticTexts["serverStatus"])
        app.tabBars.buttons["Обучение"].tap()
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        assertLabel("Синхронизировано, ревизия \(remoteRevision)", on: status)

        addCard(in: app)
        assertLabel("Синхронизировано, ревизия \(remoteRevision + 1)", on: status)
    }

    // Opt-in: только одноразовая локальная БД, никаких внешних URL.
    private func localServerURL() throws -> String {
        guard let rawPort = ProcessInfo.processInfo.environment["KANKI_STATUS_UI_PORT"] else {
            throw XCTSkip("Задайте KANKI_STATUS_UI_PORT и KANKI_STATUS_UI_TOKEN для одноразового сервера")
        }
        let port = try XCTUnwrap(UInt16(rawPort))
        return "http://127.0.0.1:\(port)"
    }

    // Второй клиент меняет ревизию настоящего сервера, не локальный снимок приложения.
    private func advanceServerRevision(url: String, token: String) async throws -> Int {
        let endpoint = try XCTUnwrap(URL(string: "\(url)/v1/snapshot"))
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let revision = try XCTUnwrap(snapshot?["revision"] as? Int)

        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"base_revision":\#(revision),"data":{"cards":[]}}"#.utf8)
        let (_, putResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((putResponse as? HTTPURLResponse)?.statusCode, 200)
        return revision + 1
    }

    private func addCard(in app: XCUIApplication) {
        app.buttons["addSessionCard"].tap()
        let question = app.descendants(matching: .any)["cardQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("Synthetic question")
        let answer = app.descendants(matching: .any)["cardAnswer"]
        answer.tap()
        answer.typeText("Synthetic answer")
        app.buttons["Добавить"].tap()
    }

    private func configureServer(in app: XCUIApplication, url: String, token: String, expected: String) {
        app.tabBars.buttons["Настройки"].tap()
        let serverURL = app.textFields["serverURL"]
        XCTAssertTrue(serverURL.waitForExistence(timeout: 10))
        serverURL.tap()
        serverURL.typeText(url)
        let serverToken = app.secureTextFields["serverToken"]
        serverToken.tap()
        serverToken.typeText(token)
        app.buttons["serverCheck"].tap()
        assertLabel(expected, on: app.staticTexts["serverStatus"], predicate: "label BEGINSWITH %@")
    }

    private func restart(_ app: XCUIApplication) {
        app.launchArguments = []
        app.terminate()
        app.launch()
    }

    private func assertLabel(_ text: String, on element: XCUIElement, predicate: String = "label == %@") {
        expectation(for: NSPredicate(format: predicate, text), evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
