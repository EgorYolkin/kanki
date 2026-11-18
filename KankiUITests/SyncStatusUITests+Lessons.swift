import Foundation
import XCTest

extension SyncStatusUITests {
    typealias WireObject = [String: Any]
    typealias WireSnapshot = (revision: Int, data: WireObject)

    private struct LessonBatch {
        let id = UUID().uuidString
        let title = "Демо урок"
        let course = "Курс \(UUID().uuidString.prefix(8))"
        let sourceURL = "https://example.org/demo-video"
        let ids = (0..<12).map { _ in UUID().uuidString }

        func question(_ index: Int) -> String { "## Демо \(index + 1)" }
        func answer(_ index: Int) -> String { "Строка \(index + 1)\n\n```\n\\n **raw**\n```" }

        func adding(to data: WireObject) -> WireObject {
            var result = data
            let now = ISO8601DateFormatter().string(from: Date())
            let cards: [WireObject] = ids.indices.map { index in
                ["id": ids[index], "question": question(index), "answer": answer(index), "createdAt": now]
            }
            let lesson: WireObject = [
                "id": id, "title": title, "course": course, "source_url": sourceURL, "card_ids": ids, "createdAt": now
            ]
            result["snapshot_version"] = 4
            result["cards"] = (data["cards"] as? [WireObject] ?? []) + cards
            result["lessons"] = (data["lessons"] as? [WireObject] ?? []) + [lesson]
            return result
        }
    }

    func exerciseFailedAppend(in app: XCUIApplication, database: URL) throws {
        app.buttons["lessonCreate"].tap()
        let title = app.textFields["lessonTitle"]
        title.tap()
        title.typeText("Демо запись")
        app.buttons["lessonSave"].tap()
        app.buttons["lessonAddCard"].tap()
        let question = app.textViews["cardQuestion"]
        question.tap()
        question.typeText("Первый")
        XCTAssertFalse(app.buttons["cardDone"].isEnabled)
        XCTAssertFalse(app.buttons["cardSaveAndAdd"].isEnabled)
        let answer = app.textViews["cardAnswer"]
        answer.tap()
        answer.typeText("Ответ")
        let save = app.buttons["cardSaveAndAdd"]
        scrollTo(save, in: app)
        save.tap()
        let count = app.staticTexts["lessonAddedCount"]
        assertLabel("Добавлено: 1", on: count)
        let original = try snapshotPayload(in: database)
        let unblock = "DROP TRIGGER IF EXISTS block_lesson_write"
        addTeardownBlock { try self.executeSQL(unblock, in: database) }
        try executeSQL("""
            CREATE TRIGGER block_lesson_write BEFORE INSERT ON learning_snapshot
            BEGIN SELECT RAISE(ABORT, 'lesson write blocked'); END;
            """, in: database)
        enterCardText(in: app, question: "Второй", answer: "Ещё один ответ")
        scrollTo(save, in: app)
        save.tap()
        let error = app.alerts["Не удалось сохранить карточку"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        error.buttons["Закрыть"].tap()
        XCTAssertEqual(count.label, "Добавлено: 1")
        XCTAssertEqual(app.textViews["cardQuestion"].value as? String, "Второй")
        XCTAssertEqual(app.textViews["cardAnswer"].value as? String, "Ещё один ответ")
        XCTAssertEqual(try snapshotPayload(in: database), original)

        try executeSQL(unblock, in: database)
        save.tap()
        assertLabel("Добавлено: 2", on: count)
        app.buttons["cardDone"].tap()
        XCTAssertTrue(app.buttons["Второй"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Первый"].exists)
        XCTAssertEqual(app.staticTexts["lessonActiveCount"].label, "Активных карточек: 2")
    }

    func exerciseAgentLesson(url: String, token: String, request: URLRequest) async throws {
        continueAfterFailure = false
        let batch = LessonBatch()
        let initial = try await readWireSnapshot(request)
        let seed = batch.adding(to: initial.data)
        let seeded = try await putSnapshot(seed, baseRevision: initial.revision, request: request)
        XCTAssertEqual(seeded, 200, "Один PUT на весь урок")

        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        configureServer(in: app, url: url, token: token, expected: "Подключено:")
        tapServerButton("serverPull", in: app)
        app.buttons["Заменить"].tap()
        assertLabel("Загружено, ревизия \(initial.revision + 1)", on: app.staticTexts["serverStatus"])
        app.tabBars.buttons["Обучение"].tap()
        openLesson(batch, in: app)
        app.buttons["lessonReview"].tap()
        XCTAssertTrue(app.staticTexts["Демо 1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reviewProgress"].label, "Карточка 1 из 12")
        app.buttons["Показать ответ"].tap()
        XCTAssertTrue(app.staticTexts["Строка 1"].exists)
        app.buttons["Хорошо"].tap()
        XCTAssertTrue(app.staticTexts["Демо 2"].waitForExistence(timeout: 5))
        app.buttons["Закрыть"].tap()
        app.navigationBars[batch.title].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Обучение"].waitForExistence(timeout: 5))
        assertLabel("Синхронизировано, ревизия \(initial.revision + 2)", on: app.staticTexts["syncStatus"])

        let synced = try await readWireSnapshot(request)
        XCTAssertEqual(synced.revision, initial.revision + 2)
        try assertReviewedBatch(batch, in: synced.data, initial: initial.data)
        let stale = try await putSnapshot(seed, baseRevision: initial.revision, request: request)
        XCTAssertEqual(stale, 409)
        let unchanged = try await readWireSnapshot(request)
        XCTAssertEqual(unchanged.revision, synced.revision)
        XCTAssertEqual(NSDictionary(dictionary: unchanged.data), NSDictionary(dictionary: synced.data))

        app.tabBars.buttons["Настройки"].tap()
        tapServerButton("serverPush", in: app)
        assertLabel("Отправлено, ревизия \(synced.revision + 1)", on: app.staticTexts["serverStatus"])
        let manual = try await readWireSnapshot(request)
        XCTAssertEqual(manual.revision, synced.revision + 1)
        XCTAssertEqual(NSDictionary(dictionary: manual.data), NSDictionary(dictionary: synced.data))
        app.tabBars.buttons["Обучение"].tap()
        let afterEditConflict = try await rejectStaleLessonEditor(batch, in: app, snapshot: manual, request: request)
        try await replaceMembershipDuringReview(batch, in: app, snapshot: afterEditConflict, request: request)
    }

    private func rejectStaleLessonEditor(
        _ batch: LessonBatch,
        in app: XCUIApplication,
        snapshot: WireSnapshot,
        request: URLRequest
    ) async throws -> WireSnapshot {
        openLesson(batch, in: app)
        app.buttons["lessonEdit"].tap()
        let title = app.textFields["lessonTitle"]
        title.tap()
        title.typeText(" локальный черновик")
        let draftTitle = title.value as? String
        XCUIDevice.shared.press(.home)
        var remoteData = snapshot.data
        var lessons = try XCTUnwrap(remoteData["lessons"] as? [WireObject])
        let index = try XCTUnwrap(lessons.firstIndex { $0["id"] as? String == batch.id })
        lessons[index]["source_url"] = "https://example.org/remote-edit"
        remoteData["lessons"] = lessons
        let status = try await putSnapshot(remoteData, baseRevision: snapshot.revision, request: request)
        XCTAssertEqual(status, 200)
        app.activate()
        XCTAssertTrue(app.staticTexts["lessonMetadataConflict"].waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, draftTitle)
        app.buttons["lessonSave"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Не удалось сохранить урок:")).firstMatch.exists)
        XCTAssertEqual(title.value as? String, draftTitle, "Не терять ввод после отклонённого сохранения")
        app.buttons["Отмена"].tap()
        app.navigationBars[batch.title].buttons.element(boundBy: 0).tap()
        let remote = try await readWireSnapshot(request)
        XCTAssertEqual(remote.revision, snapshot.revision + 1)
        XCTAssertEqual(NSDictionary(dictionary: remote.data), NSDictionary(dictionary: remoteData))
        return remote
    }

    private func assertReviewedBatch(_ batch: LessonBatch, in data: WireObject, initial: WireObject) throws {
        XCTAssertEqual(data["snapshot_version"] as? Int, 4)
        let lessons = try XCTUnwrap(data["lessons"] as? [WireObject])
        let lesson = try XCTUnwrap(lessons.first { $0["id"] as? String == batch.id })
        XCTAssertEqual(lesson["card_ids"] as? [String], batch.ids)
        XCTAssertEqual(lesson["title"] as? String, batch.title)
        XCTAssertEqual(lesson["course"] as? String, batch.course)
        XCTAssertEqual(lesson["source_url"] as? String, batch.sourceURL)
        let cards = try XCTUnwrap(data["cards"] as? [WireObject])
        XCTAssertEqual(cards.count, (initial["cards"] as? [WireObject] ?? []).count + 12)
        for (index, id) in batch.ids.enumerated() {
            let card = try XCTUnwrap(cards.first { $0["id"] as? String == id })
            XCTAssertEqual(card["question"] as? String, batch.question(index))
            XCTAssertEqual(card["answer"] as? String, batch.answer(index))
        }
        let reviews = try XCTUnwrap(data["reviews"] as? [WireObject])
        XCTAssertEqual(reviews.count, (initial["reviews"] as? [WireObject] ?? []).count + 1)
        XCTAssertEqual(reviews.last?["cardID"] as? String, batch.ids[0])
        XCTAssertEqual(reviews.last?["rating"] as? Int, 3)
        let schedules = try XCTUnwrap(data["schedules"] as? WireObject)
        XCTAssertNotNil(schedules[batch.ids[0]])
        XCTAssertEqual(schedules.count, (initial["schedules"] as? WireObject ?? [:]).count + 1)
    }

    private func replaceMembershipDuringReview(
        _ batch: LessonBatch,
        in app: XCUIApplication,
        snapshot: WireSnapshot,
        request: URLRequest
    ) async throws {
        openLesson(batch, in: app)
        app.buttons["lessonReview"].tap()
        XCTAssertTrue(app.staticTexts["Демо 1"].waitForExistence(timeout: 5))
        app.buttons["Показать ответ"].tap()
        scrollTo(app.buttons["Хорошо"], in: app)
        XCTAssertTrue(app.buttons["Хорошо"].isHittable)
        // Меняется только членство: сама карточка и её расписание ещё существуют.
        XCUIDevice.shared.press(.home)
        var data = snapshot.data
        var lessons = try XCTUnwrap(data["lessons"] as? [WireObject])
        let index = try XCTUnwrap(lessons.firstIndex { $0["id"] as? String == batch.id })
        lessons[index]["card_ids"] = Array(batch.ids.dropFirst())
        data["lessons"] = lessons
        let status = try await putSnapshot(data, baseRevision: snapshot.revision, request: request)
        XCTAssertEqual(status, 200)
        app.activate()
        assertReviewDismissed(in: app)
        XCTAssertFalse(app.buttons["Хорошо"].exists, "Нельзя оценить карточку из заменённого занятия")

        app.terminate()
        app.launchArguments = []
        app.launch()
        openLesson(batch, in: app)
        app.buttons["lessonReview"].tap()
        XCTAssertTrue(app.staticTexts["Демо 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reviewProgress"].label, "Карточка 1 из 11")
        let current = try await readWireSnapshot(request)
        XCTAssertEqual(current.revision, snapshot.revision + 1)
        XCTAssertEqual(NSDictionary(dictionary: current.data), NSDictionary(dictionary: data))
    }

    private func assertReviewDismissed(in app: XCUIApplication) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["reviewProgress"])
        waitForExpectations(timeout: 10)
    }

    private func openLesson(_ batch: LessonBatch, in app: XCUIApplication) {
        let catalog = app.buttons["lessonCatalog"]
        scrollTo(catalog, in: app)
        catalog.tap()
        let course = app.buttons[batch.course]
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap()
        let result = app.buttons[batch.title]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["lessonAddCard"].waitForExistence(timeout: 5))
    }

    private func tapServerButton(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        scrollTo(button, in: app)
        button.tap()
    }

    func readWireSnapshot(_ request: URLRequest) async throws -> WireSnapshot {
        let (body, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? WireObject)
        XCTAssertEqual(envelope["schema_version"] as? Int, 1)
        let data = envelope["data"] as? WireObject ?? [:]
        guard (data["snapshot_version"] as? Int ?? 3) <= 4 else {
            throw NSError(domain: "Тест не меняет снимки будущей версии", code: 1)
        }
        return (try XCTUnwrap(envelope["revision"] as? Int), data)
    }

    private func putSnapshot(_ data: WireObject, baseRevision: Int, request: URLRequest) async throws -> Int {
        var put = request
        put.httpMethod = "PUT"
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let envelope: WireObject = ["schema_version": 1, "base_revision": baseRevision, "data": data]
        put.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let (_, response) = try await URLSession.shared.data(for: put)
        return try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
    }
}
