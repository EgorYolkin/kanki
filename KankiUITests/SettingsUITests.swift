import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    func testAppearancePersistsAndStatusesStayHonest() {
        let app = XCUIApplication()
        app.launchEnvironment["KANKI_CARD_LIBRARY_TEST_ID"] = UUID().uuidString

        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.staticTexts["Сервер не подключён"].waitForExistence(timeout: 5))

        app.buttons["Тёмное"].tap()
        XCTAssertTrue(app.buttons["Тёмное"].isSelected)
        XCTAssertTrue(app.buttons["Системное"].exists)

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["О приложении"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Версия'")).firstMatch.exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.buttons["Тёмное"].isSelected)

        app.buttons["Системное"].tap()
        XCTAssertTrue(app.buttons["Системное"].isSelected)
    }
}
