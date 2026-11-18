import XCTest

/// macOS-оболочка: приложение открывается окном, разделы-заготовки скрыты
/// по умолчанию и возвращаются тумблерами в настройках; видимые разделы
/// переключаются горячими клавишами из меню `SectionCommands`.
final class MacShellUITests: XCTestCase {
    @MainActor
    func testSectionsOpenFromKeyboardShortcuts() throws {
        let app = try launchIsolatedApp()

        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 20))

        // Заготовки скрыты: ⌘2 и ⌘3 не переключают раздел.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertEqual(app.windows.firstMatch.title, "Обучение")

        app.typeKey("5", modifierFlags: .command)
        XCTAssertEqual(waitForWindowTitle("Статистика", in: app), .completed)

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

    @MainActor
    func testNativeLessonEditorsKeepReturnAndRenderMarkdownAfterRelaunch() throws {
        let app = try launchIsolatedApp()
        app.buttons["lessonCreate"].click()
        let title = app.textFields["lessonTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.click()
        title.typeText("Введение")
        app.descendants(matching: .any)["lessonCourse"].firstMatch.click()
        app.menuItems["Новый курс…"].click()
        let course = app.textFields["lessonNewCourse"]
        course.click()
        course.typeText("Swift")
        app.buttons["lessonSave"].click()
        app.buttons["lessonAddCard"].click()

        let question = app.textViews["cardQuestion"]
        let answer = app.textViews["cardAnswer"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        question.click()
        question.typeText("**Демо вопрос**")
        answer.click()
        answer.typeText("## Демо ответ")
        answer.typeKey(.return, modifierFlags: [])
        answer.typeKey(.return, modifierFlags: [])
        answer.typeText("- **Пункт**")
        XCTAssertEqual(answer.value as? String, "## Демо ответ\n\n- **Пункт**")
        app.buttons["cardSaveAndAdd"].click()
        XCTAssertFalse(app.buttons["cardSaveAndAdd"].isEnabled)
        app.buttons["cardDone"].click()
        XCTAssertTrue(app.buttons["Демо вопрос"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        let latest = app.buttons["lessonLatest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 20))
        XCTAssertEqual(latest.label, "Введение · Swift")
        app.buttons["lessonReview"].click()
        XCTAssertTrue(app.staticTexts["Демо вопрос"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Демо ответ"].exists)
        app.buttons["Показать ответ"].click()
        XCTAssertTrue(app.staticTexts["Демо ответ"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Пункт"].exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Демо Markdown в уроке macOS"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Легко"].click()
        XCTAssertTrue(app.buttons["reviewFinish"].waitForExistence(timeout: 10))
        app.buttons["reviewFinish"].click()
        XCTAssertTrue(app.staticTexts["Оценок: 1"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func launchIsolatedApp() throws -> XCUIApplication {
        continueAfterFailure = false
        let home = FileManager.default.temporaryDirectory.appending(path: "KankiUITest-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["CFFIXED_USER_HOME"] = home.path
        app.launchEnvironment["HOME"] = home.path
        // Новый home уже пуст. Не сбрасываем рабочую БД или Keychain пользователя.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-serverURL", "", "--reset-sections"]
        addTeardownBlock { @MainActor in
            app.terminate()
            try FileManager.default.removeItem(at: home)
        }
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60))
        return app
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
        target.click()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, "Не включён \(identifier): \(target.debugDescription)")
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
