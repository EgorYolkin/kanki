import Foundation
import XCTest

@MainActor
final class StatisticsUITests: UITestCase {
    func testStatisticsAlwaysAvailableWithoutConnection() {
        let app = launchClean()
        let tab = app.tabBars.buttons["Статистика"]
        tab.tap()
        XCTAssertTrue(app.navigationBars["Статистика"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Сервер не настроен"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Активности пока нет"].exists)

        app.tabBars.buttons["Настройки"].tap()
        enableSectionToggles(in: app)
        tab.tap()
        XCTAssertTrue(app.staticTexts["Сервер не настроен"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["refreshStatistics"].isEnabled)
    }

    func testStatisticsReportsUnreachableServer() {
        let app = launchClean()
        configure(app, url: "http://127.0.0.1:9", token: "offline-test", expected: "Не удалось связаться")
        app.tabBars.buttons["Статистика"].tap()
        XCTAssertTrue(app.staticTexts["Не удалось загрузить статистику"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Активности пока нет"].exists)
        XCTAssertTrue(app.buttons["refreshStatistics"].isEnabled)
    }

    func testPopulatedDashboardRefreshesFromLoopbackServer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawPort = environment["KANKI_STATISTICS_UI_PORT"] else {
            throw XCTSkip("Для проверки нужен одноразовый локальный сервер: KANKI_STATISTICS_UI_PORT и KANKI_STATISTICS_UI_TOKEN")
        }
        let port = try XCTUnwrap(UInt16(rawPort))
        let token = try XCTUnwrap(environment["KANKI_STATISTICS_UI_TOKEN"])
        let url = "http://127.0.0.1:\(port)"
        try await post(events: demoActivity(), url: url, token: token)

        let app = launchClean()
        configure(app, url: url, token: token, expected: "Подключено:")
        app.tabBars.buttons["Статистика"].tap()
        let total = element("statisticsTotalReviews", in: app)
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        let before = try XCTUnwrap(Int(total.value as? String ?? ""))
        XCTAssertGreaterThanOrEqual(before, 12)
        let streak = try XCTUnwrap(Int(element("statisticsStreak", in: app).value as? String ?? ""))
        XCTAssertGreaterThanOrEqual(streak, 4)
        attach("Статистика — итоги и активность", in: app)

        let review = Event(kind: "imported_review", timestamp: Date(), rating: 3, topic: "Демо: география")
        try await post(events: [review], url: url, token: token)
        app.buttons["refreshStatistics"].tap()
        waitForTotal(before + 1, on: total)

        let calendar = app.segmentedControls["statisticsCalendarMetric"]
        scrollTo(calendar, in: app)
        calendar.buttons["Посещения"].tap()
        XCTAssertTrue(calendar.buttons["Посещения"].isSelected)
        let day = app.staticTexts["statisticsCalendarDay"]
        XCTAssertTrue(day.label.contains("Посещений:"))
        XCTAssertTrue(day.label.contains("Повторений:"))
        attach("Статистика — календарь посещений", in: app)

        let topic = element("statisticsTopic-Демо: география", in: app)
        scrollTo(topic, in: app)
        XCTAssertTrue(topic.exists)
        XCTAssertTrue((topic.value as? String)?.contains("Повторений:") == true)
        attach("Статистика — оценки и темы", in: app)
    }

    private func waitForTotal(_ count: Int, on element: XCUIElement) {
        let updated = NSPredicate(format: "exists == true AND value == %@", String(count))
        expectation(for: updated, evaluatedWith: element)
        waitForExpectations(timeout: 10)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server", "--reset-sections"]
        app.launch()
        return app
    }

    private func configure(_ app: XCUIApplication, url: String, token: String, expected: String) {
        app.tabBars.buttons["Настройки"].tap()
        let urlField = app.textFields["serverURL"]
        scrollTo(urlField, in: app)
        urlField.tap()
        urlField.typeText(url)
        let tokenField = app.secureTextFields["serverToken"]
        tokenField.tap()
        tokenField.typeText(token)
        app.buttons["serverCheck"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", expected), evaluatedWith: app.staticTexts["serverStatus"])
        waitForExpectations(timeout: 10)
        app.terminate()
        app.launchArguments = []
        app.launch()
    }

    private struct Event: Encodable {
        let id = UUID()
        let kind: String
        let timestamp: Date
        var rating: Int?
        var topic: String?
    }

    private func demoActivity() throws -> [Event] {
        let now = Date()
        let offsets = [38, 33, 26, 17, 13, 9, 7, 5, 3, 2, 1, 0]
        let topics = ["Демо: география", "Демо: история", "Демо: биология"]
        var events: [Event] = []
        for (index, offset) in offsets.enumerated() {
            let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -offset, to: now))
            events.append(Event(kind: "visit", timestamp: date))
            for _ in 0..<(index % 3 + 1) {
                events.append(Event(kind: "imported_review", timestamp: date, rating: index % 4 + 1, topic: topics[index % topics.count]))
            }
        }
        return events
    }

    private func post(events: [Event], url: String, token: String) async throws {
        let endpoint = try XCTUnwrap(URL(string: "\(url)/v1/statistics/events"))
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(["events": events])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
    }

    private func attach(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
