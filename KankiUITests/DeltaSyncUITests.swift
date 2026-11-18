import XCTest

@MainActor
final class DeltaSyncUITests: XCTestCase {
    private let fixtureToken = "stage8-synthetic-token"
    private let deviceToken = "stage8-synthetic-device-token"
    private let rotatedToken = "stage8-synthetic-rotated-token"

    func testTwoPullsAndOfflineReviewWithLostAcknowledgement() async throws {
        guard let raw = ProcessInfo.processInfo.environment["KANKI_DELTA_FIXTURE_URL"] else {
            throw XCTSkip("Запустите локальный стенд из experiments/README.md")
        }
        let url = try XCTUnwrap(URL(string: raw))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "127.0.0.1")
        guard url.scheme == "https", url.host == "127.0.0.1" else { return }

        try await fixture("seed", at: url)
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        assertRejectedCredentialsNotSaved(in: app, address: raw)
        enterDeltaCredentials(in: app, address: raw, token: deviceToken)
        sync(in: app, expecting: "Прочитано: 1. Доставлено: 0.")
        app.tabBars.buttons["Обучение"].tap()
        XCTAssertFalse(app.staticTexts["syncStatus"].exists, "Дельта не включает снимки")
        showImportedList(in: app)
        XCTAssertTrue(app.buttons["Синтетика: дельта 1"].waitForExistence(timeout: 5))

        try await fixture("update", at: url)
        showSettings(in: app)
        sync(in: app, expecting: "Прочитано: 1. Доставлено: 0.")
        try await fixture("offline", at: url)
        showImportedList(in: app)
        let card = app.buttons["Синтетика: дельта 2"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        app.buttons["revealImportedAnswer"].tap()
        app.buttons["importedRating-3"].tap()
        XCTAssertTrue(app.staticTexts["importedCardDue"].waitForExistence(timeout: 5))

        restart(app)
        showImportedList(in: app)
        card.tap()
        assertOneReview(in: app)
        showSettings(in: app)
        sync(in: app, expecting: "Ошибка сервера: 503")

        try await fixture("update-again", at: url)
        editDeltaAddress(in: app)
        enterDeltaToken(in: app, token: rotatedToken)
        try await fixture("lose-ack", at: url)
        sync(in: app, expecting: "Прочитано: 1. Доставлено: 0.", containing: "Не удалось отправить: Ошибка сервера: 503")
        let afterLostAck = try await stream(at: url)
        XCTAssertEqual(afterLostAck.filter { $0 == "review" }.count, 1)
        restart(app)
        showSettings(in: app)
        sync(in: app, expecting: "Прочитано: 1. Доставлено: 1.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Delta sync after offline replay"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        sync(in: app, expecting: "Прочитано: 0. Доставлено: 0.")
        let afterRetry = try await stream(at: url)
        XCTAssertEqual(afterRetry, ["publication", "publication", "publication", "review"])
    }

    private func assertRejectedCredentialsNotSaved(in app: XCUIApplication, address: String) {
        showSettings(in: app)
        enterDeltaCredentials(in: app, address: address, token: "rejected-synthetic-token")
        sync(in: app, expecting: "Токен отклонён")
        restart(app)
        showSettings(in: app)
        let field = app.textFields["deltaURL"]
        scrollTo(field, in: app)
        XCTAssertNotEqual(field.value as? String, address)
    }

    private func enterDeltaCredentials(in app: XCUIApplication, address: String, token: String) {
        let field = app.textFields["deltaURL"]
        scrollTo(field, in: app)
        field.tap()
        field.typeText(address)
        enterDeltaToken(in: app, token: token)
    }

    private func editDeltaAddress(in app: XCUIApplication) {
        let address = app.textFields["deltaURL"]
        scrollTo(address, in: app, backwards: true)
        address.tap()
        // Editing the address clears the token even if the user restores the same URL.
        address.typeText("/" + XCUIKeyboardKey.delete.rawValue)
        XCTAssertFalse(app.staticTexts["deltaStatus"].exists)
    }

    private func enterDeltaToken(in app: XCUIApplication, token: String) {
        let secret = app.secureTextFields["deltaToken"]
        scrollTo(secret, in: app)
        secret.tap()
        secret.typeText(token + "\n")
    }

    private func restart(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = []
        app.launch()
    }

    private func showSettings(in app: XCUIApplication) {
        app.tabBars.buttons["Настройки"].tap()
    }

    private func showImportedList(in app: XCUIApplication) {
        app.tabBars.buttons["Обучение"].tap()
        let imported = app.buttons["importedCards"]
        if imported.exists { imported.tap() }
    }

    private func assertOneReview(in app: XCUIApplication) {
        let history = app.buttons["importedCardHistory"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()
        let good = app.staticTexts.matching(identifier: "Хорошо")
        XCTAssertTrue(good.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(good.count, 1)
    }

    private func sync(in app: XCUIApplication, expecting prefix: String, containing detail: String? = nil) {
        let button = app.buttons["deltaSync"]
        scrollTo(button, in: app)
        XCTAssertTrue(button.isHittable)
        button.tap()
        var statuses = app.staticTexts.matching(identifier: "deltaStatus")
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        if let detail {
            statuses = statuses.matching(NSPredicate(format: "label CONTAINS %@", detail))
        }
        XCTAssertTrue(statuses.firstMatch.waitForExistence(timeout: 20), "Ожидался статус: \(prefix)")
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, backwards: Bool = false) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            if backwards { app.swipeDown() } else { app.swipeUp() }
        }
    }

    private func fixture(_ command: String, at url: URL) async throws {
        _ = try await request(url.appending(path: "fixture/\(command)"), method: "POST")
    }

    private func stream(at url: URL) async throws -> [String] {
        struct Event: Decodable { let kind: String }
        struct Change: Decodable { let event: Event }
        struct Page: Decodable { let changes: [Change] }
        let changes = url.appending(path: "v1/changes").appending(queryItems: [.init(name: "since", value: "0")])
        return try await JSONDecoder().decode(Page.self, from: request(changes, method: "GET")).changes.map(\.event.kind)
    }

    private func request(_ url: URL, method: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("Bearer \(fixtureToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return data
    }
}
