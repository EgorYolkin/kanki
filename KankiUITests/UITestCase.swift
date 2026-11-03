import XCTest

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

    /// Кнопка «плюс» стоит в правом нижнем углу над таб-баром;
    /// отдельной FAB повторения больше нет — обучение запускает кнопка в списке.
    func assertAddButton(in app: XCUIApplication) {
        let add = app.buttons["addSessionCard"]
        let tabBar = app.tabBars.firstMatch

        XCTAssertTrue(add.exists, "Кнопка «плюс» должна быть видна")
        XCTAssertEqual(add.frame.width, 44, accuracy: 1)
        XCTAssertEqual(add.frame.height, 44, accuracy: 1)
        XCTAssertGreaterThan(add.frame.midX, app.frame.midX, "Кнопка должна быть в правой половине экрана")
        XCTAssertLessThanOrEqual(add.frame.maxY, tabBar.frame.minY, "Кнопка не должна перекрывать таб-бар")
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
        questionField.tap()
        questionField.typeText(question)
        answerField.tap()
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
        app.navigationBars["Все карточки"].buttons.element(boundBy: 0).tap()
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
}
