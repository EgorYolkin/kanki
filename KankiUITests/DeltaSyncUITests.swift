import XCTest

@MainActor
final class DeltaSyncUITests: XCTestCase {
    private let token = "stage8-synthetic-token"

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
        showSettings(in: app)
        let address = app.textFields["serverURL"]
        scrollTo(address, in: app)
        address.tap()
        address.typeText(raw)
        let secret = app.secureTextFields["serverToken"]
        scrollTo(secret, in: app)
        secret.tap()
        secret.typeText(token + "\n")
        sync(in: app, expecting: "Прочитано: 1. Доставлено: 0.")
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

        app.terminate()
        app.launchArguments = []
        app.launch()
        showImportedList(in: app)
        card.tap()
        assertOneReview(in: app)
        showSettings(in: app)
        sync(in: app, expecting: "Ошибка сервера: 503")

        try await fixture("lose-ack", at: url)
        sync(in: app, expecting: "Ошибка сервера: 503")
        let afterLostAck = try await stream(at: url)
        XCTAssertEqual(afterLostAck.filter { $0 == "review" }.count, 1)
        sync(in: app, expecting: "Прочитано: 1. Доставлено: 1.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Delta sync after offline replay"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        sync(in: app, expecting: "Прочитано: 0. Доставлено: 0.")
        let afterRetry = try await stream(at: url)
        XCTAssertEqual(afterRetry, ["publication", "publication", "review"])
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

    private func sync(in app: XCUIApplication, expecting prefix: String) {
        let button = app.buttons["deltaSync"]
        scrollTo(button, in: app)
        XCTAssertTrue(button.isHittable)
        button.tap()
        let status = app.staticTexts.matching(identifier: "deltaStatus")
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 20), app.staticTexts["deltaStatus"].label)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return data
    }
}
