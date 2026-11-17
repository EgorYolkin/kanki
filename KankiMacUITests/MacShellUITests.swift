import XCTest

/// macOS-оболочка: приложение открывается окном, разделы-заготовки скрыты
/// по умолчанию и возвращаются тумблерами в настройках; видимые разделы
/// переключаются горячими клавишами из меню `SectionCommands`.
final class MacShellUITests: XCTestCase {
    @MainActor
    func testSectionsOpenFromKeyboardShortcuts() {
        let app = XCUIApplication()
        // Без этого macOS может восстановить прошлое состояние «окон нет»
        // и не открыть новое окно, из-за чего тест не найдёт ни одного Window.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--reset-store", "--reset-sections"]
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60))
        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 20))

        // Заготовки скрыты: ⌘2 и ⌘3 не переключают раздел.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")

        app.typeKey("4", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Настройки", in: app), .completed)
        // На macOS подпись `Label` попадает в `value`, а не в `label`, поэтому
        // экран настроек проверяется по accessibilityIdentifier кнопки темы.
        XCTAssertTrue(app.buttons["appearance-system"].waitForExistence(timeout: 20))

        turnOn("showNotesSection", in: app)
        turnOn("showGraphSection", in: app)

        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Заметки", in: app), .completed)

        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Граф", in: app), .completed)

        app.typeKey("4", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Настройки", in: app), .completed)

        app.typeKey("1", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Обучение", in: app), .completed)
    }

    /// Включает тумблер раздела в настройках; macOS показывает Toggle
    /// как switch или checkbox, поэтому пробуем оба варианта.
    @MainActor
    private func turnOn(_ identifier: String, in app: XCUIApplication) {
        let control = app.switches.matching(identifier: identifier).firstMatch
        let checkBox = app.checkBoxes.matching(identifier: identifier).firstMatch
        let any = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let target = control.exists ? control : (checkBox.exists ? checkBox : any)
        XCTAssertTrue(target.waitForExistence(timeout: 20), "Нет тумблера \(identifier)")
        target.tap()
    }

    /// Заголовок окна меняется вместе с `navigationTitle` раздела, поэтому
    /// дожидаемся именно смены заголовка, а не появления нового элемента.
    @MainActor
    private func waitForWindowTitle(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 20
    ) -> XCTWaiter.Result {
        let predicate = NSPredicate(format: "title == %@", title)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: app.windows.firstMatch
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout)
    }
}
