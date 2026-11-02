import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    func testAppearancePersistsAndStatusesStayHonest() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-server"]
        app.launch()

        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.buttons["appearance-dark"].exists)

        app.buttons["appearance-dark"].tap()
        XCTAssertTrue(app.buttons["appearance-dark"].isSelected)
        XCTAssertLessThan(averageBrightness(app), 0.4, "Тёмная тема должна затемнять интерфейс")

        app.buttons["appearance-light"].tap()
        XCTAssertTrue(app.buttons["appearance-light"].isSelected)
        XCTAssertGreaterThan(averageBrightness(app), 0.6, "Светлая тема должна осветлять интерфейс")

        app.buttons["appearance-dark"].tap()
        XCTAssertTrue(app.buttons["appearance-dark"].isSelected)
        XCTAssertLessThan(averageBrightness(app), 0.4, "Повторное переключение на тёмную тему должно работать")

        app.buttons["appearance-light"].tap()
        XCTAssertTrue(app.buttons["appearance-light"].isSelected)
        XCTAssertGreaterThan(averageBrightness(app), 0.6, "Повторное переключение на светлую тему должно работать")

        let serverURL = app.textFields["serverURL"]
        let serverCheck = app.buttons["serverCheck"]
        scrollTo(serverCheck, in: app)
        XCTAssertTrue(serverURL.exists)
        XCTAssertTrue(app.secureTextFields["serverToken"].exists)
        XCTAssertTrue(app.buttons["serverPush"].exists)
        XCTAssertTrue(app.buttons["serverPull"].exists)
        XCTAssertEqual(app.staticTexts["serverStatus"].label, "Не подключён")

        serverCheck.tap()
        let invalidURL = app.staticTexts["Укажите адрес вида http://100.x.y.z:8000"]
        XCTAssertTrue(invalidURL.waitForExistence(timeout: 5))

        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["О приложении"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Версия'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Пробная сборка'")).firstMatch.exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.buttons["appearance-light"].isSelected)
        XCTAssertGreaterThan(averageBrightness(app), 0.6, "Светлая тема должна сохраняться после перезапуска")

        app.buttons["appearance-system"].tap()
        XCTAssertTrue(app.buttons["appearance-system"].isSelected)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func averageBrightness(_ app: XCUIApplication) -> CGFloat {
        let image = app.screenshot().image
        guard let source = image.cgImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .medium
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        context?.draw(source, in: rect)
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }
}
