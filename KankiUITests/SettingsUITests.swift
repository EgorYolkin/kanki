import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    func testAppearancePersistsAndStatusesStayHonest() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.staticTexts["Сервер не подключён"].exists)
        XCTAssertTrue(app.staticTexts["Карточки и оценки хранятся на этом iPhone. Сервер не подключён, синхронизация не настроена."].exists)

        app.buttons["Тёмное"].tap()
        XCTAssertTrue(app.buttons["Тёмное"].isSelected)
        XCTAssertTrue(app.buttons["Системное"].exists)

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["О приложении"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Версия'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Пробная сборка'")).firstMatch.exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.buttons["Тёмное"].isSelected)

        app.buttons["Системное"].tap()
        XCTAssertTrue(app.buttons["Системное"].isSelected)
    }
}
