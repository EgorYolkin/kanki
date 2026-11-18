import XCTest

@MainActor
extension XCUIApplication {
    func sectionButton(_ title: String) -> XCUIElement {
        let tabBar = tabBars.firstMatch
        // На адаптивной раскладке UIKit отдаёт кнопки боковой панели внутри Toolbar.
        return tabBar.exists ? tabBar.buttons[title] : toolbars.buttons[title]
    }
}

/// Общие шаги UI-тестов: навигация «Обучение» ↔ «Все карточки»,
/// создание карточек с категорией и управление категориями.
@MainActor
class UITestCase: XCTestCase {
    enum Deck {
        case none
        case existing(String)
        case new(String)
    }

    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    /// Кнопка «плюс» справа и не перекрывает системную навигацию.
    func assertAddButton(in app: XCUIApplication) {
        let add = app.buttons["addSessionCard"]

        XCTAssertTrue(add.exists, "Кнопка «плюс» должна быть видна")
        XCTAssertEqual(add.frame.width, 44, accuracy: 1)
        XCTAssertEqual(add.frame.height, 44, accuracy: 1)
        XCTAssertGreaterThan(add.frame.midX, app.frame.midX, "Кнопка должна быть в правой половине экрана")
        assertDoesNotOverlapSectionNavigation(add, in: app)
    }

    func assertDoesNotOverlapSectionNavigation(_ button: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            XCTAssertLessThanOrEqual(button.frame.maxY, tabBar.frame.minY, "Кнопка перекрывает таб-бар")
        } else {
            let sidebarButton = app.sectionButton("Обучение")
            XCTAssertTrue(sidebarButton.isHittable, "Нет доступной кнопки боковой панели")
            XCTAssertLessThanOrEqual(button.frame.maxX, sidebarButton.frame.minX, "Кнопка перекрывает боковую панель")
        }
    }

    func addCard(
        in app: XCUIApplication,
        question: String,
        answer: String,
        deck: Deck = .none
    ) {
        app.buttons["addSessionCard"].tap()
        XCTAssertTrue(app.navigationBars["Карточка"].waitForExistence(timeout: 5))

        switch deck {
        case .none:
            break
        case .existing(let name):
            chooseDeck(in: app, option: name)
        case .new(let name):
            chooseDeck(in: app, option: "Новая категория…")
            let nameField = app.textFields["newDeckName"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Нет поля ввода новой категории")
            nameField.tap()
            nameField.typeText(name)
        }

        let questionField = app.descendants(matching: .any)["cardQuestion"]
        let answerField = app.descendants(matching: .any)["cardAnswer"]
        // У многострочного поля первая строка выше центра области.
        questionField.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        questionField.typeText(question)
        answerField.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        answerField.typeText(answer)
        let add = app.buttons["Добавить"]
        XCTAssertTrue(add.isEnabled, "Кнопка «Добавить» заблокирована")
        add.tap()
        XCTAssertTrue(app.navigationBars["Обучение"].waitForExistence(timeout: 5))
    }

    func chooseDeck(in app: XCUIApplication, option: String) {
        let picker = app.descendants(matching: .any).matching(identifier: "cardDeckPicker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Нет пикера категории")
        picker.tap()
        let choice = app.buttons[option]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Нет пункта «\(option)» в пикере")
        choice.tap()
    }

    func openAllCards(in app: XCUIApplication) {
        let link = app.buttons["Все карточки"]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Нет перехода «Все карточки»")
        link.tap()
        XCTAssertTrue(app.navigationBars["Все карточки"].waitForExistence(timeout: 5))
    }

    func backToLearning(in app: XCUIApplication) {
        let back = app.tabBars.firstMatch.exists
            ? app.navigationBars["Все карточки"].buttons.element(boundBy: 0)
            : app.toolbars.buttons["BackButton"]
        back.tap()
        XCTAssertTrue(app.navigationBars["Обучение"].waitForExistence(timeout: 5))
    }

    func categoryRow(in app: XCUIApplication, named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func deckChip(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "cardDeckChip").firstMatch
    }

    func renameCategory(in app: XCUIApplication, from oldName: String, to newName: String) {
        let row = categoryRow(in: app, named: oldName)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Нет строки категории «\(oldName)»")
        row.press(forDuration: 1.2)

        let rename = app.buttons["Переименовать…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "Нет пункта «Переименовать…» в контекстном меню")
        rename.tap()

        let alert = app.alerts["Переименовать категорию"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Не открылся диалог переименования")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(newName)
        alert.buttons["Переименовать"].tap()
        XCTAssertTrue(categoryRow(in: app, named: newName).waitForExistence(timeout: 5))
    }

    /// Включает тумблеры разделов «Заметки» и «Граф» в настройках.
    /// Полный свайп проскакивает секцию, поэтому крутим список короткими драгами.
    func enableSectionToggles(in app: XCUIApplication) {
        turnOnSectionToggle("showNotesSection", in: app)
        turnOnSectionToggle("showGraphSection", in: app)
    }

    private func turnOnSectionToggle(_ identifier: String, in app: XCUIApplication) {
        let control = app.switches[identifier]
        for _ in 0..<10 {
            if control.isHittable { break }
            dragListUpSlightly(in: app)
        }
        XCTAssertTrue(control.isHittable, "Тумблер \(identifier) вне экрана")
        if app.tabBars.firstMatch.exists {
            // Элемент накрывает и подпись, и кноб: тап в центр попадает в текст.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        } else {
            // В широкой строке 90% ширины не попадают в дочерний Switch.
            let knob = control.switches.firstMatch
            XCTAssertTrue(knob.isHittable, "Кноб \(identifier) вне экрана")
            knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, "Тумблер \(identifier) не включился")
    }

    private func dragListUpSlightly(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
    }
}
