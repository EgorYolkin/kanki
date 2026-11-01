import XCTest

/// macOS-оболочка: приложение открывается окном, разделы переключаются
/// горячими клавишами ⌘1–⌘4 из меню `SectionCommands`.
final class MacShellUITests: XCTestCase {
    @MainActor
    func testSectionsOpenFromKeyboardShortcuts() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60))
        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 20))

        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Заметки", in: app), .completed)

        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Граф", in: app), .completed)

        app.typeKey("4", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Настройки", in: app), .completed)
        // На macOS подпись `Label` попадает в `value`, а не в `label`, поэтому
        // экран настроек проверяется по accessibilityIdentifier пикера.
        XCTAssertTrue(app.radioGroups["appearancePicker"].waitForExistence(timeout: 20))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Обучение", in: app), .completed)
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
