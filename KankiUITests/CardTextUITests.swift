import XCTest

@MainActor
final class CardTextUITests: UITestCase {
    func testRepairPreviewChangesOnlySelectedPairAfterSavingEdit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        let question = "[Первая](https://example.org/demo)\n\n**вторая**"
        let original = #"Строка\nОтвет C:\new"#
        let repaired = "Строка\nОтвет C:\\new"
        addCard(in: app, question: question, answer: original)
        openAllCards(in: app)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Ответ")
        let card = app.buttons["Первая вторая"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Поиск должен находить и текст ответа")
        XCTAssertFalse(app.staticTexts[original].exists)
        XCTAssertFalse(app.links["Первая"].exists, "В кратком вопросе не должно быть ссылки")
        card.tap()
        XCTAssertTrue(app.links["Первая"].waitForExistence(timeout: 5))
        app.buttons["editSessionCard"].tap()
        let editor = app.textViews["cardAnswer"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["cardQuestion"].value as? String, question)
        XCTAssertEqual(editor.value as? String, original)
        chooseFirstMatch(in: app, original: original, repaired: repaired)
        app.buttons["newlineCancel"].tap()
        XCTAssertEqual(editor.value as? String, original)

        chooseFirstMatch(in: app, original: original, repaired: repaired)
        app.buttons["newlineApply"].tap()
        XCTAssertEqual(editor.value as? String, repaired)
        app.buttons["Отмена"].tap()
        app.buttons["editSessionCard"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, original, "Отмена правки не должна менять хранилище")

        chooseFirstMatch(in: app, original: original, repaired: repaired)
        app.buttons["newlineApply"].tap()
        app.buttons["Сохранить"].tap()
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts[repaired].waitForExistence(timeout: 5))
        app.buttons["editSessionCard"].tap()
        XCTAssertEqual(editor.value as? String, repaired)
        XCTAssertEqual(app.textViews["cardQuestion"].value as? String, question)
    }

    private func chooseFirstMatch(in app: XCUIApplication, original: String, repaired: String) {
        let repair = app.buttons["cardAnswerRepair"]
        scrollTo(repair, in: app)
        repair.tap()
        let apply = app.buttons["newlineApply"]
        let preview = app.staticTexts["newlinePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertFalse(apply.isEnabled, "Ни одна замена не выбирается автоматически")
        XCTAssertEqual(preview.label, original)
        let matches = app.descendants(matching: .any)
        XCTAssertTrue(matches["newlineMatch1"].exists, "Буквальная последовательность в C:\\new — отдельное совпадение")
        let occurrence = matches["newlineMatch0"].firstMatch
        // У Toggle на iOS подпись и переключатель занимают одну строку.
        occurrence.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(apply.isEnabled)
        XCTAssertEqual(preview.label, repaired)
    }
}
