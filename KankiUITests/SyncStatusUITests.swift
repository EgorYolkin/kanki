import Foundation
import SQLite3
import XCTest

@MainActor
final class SyncStatusUITests: XCTestCase {
    func testStatusHiddenWithoutConfiguredServer() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        app.tabBars.buttons["Обучение"].tap()
        let status = app.staticTexts["syncStatus"]
        XCTAssertFalse(status.waitForExistence(timeout: 2), "Без настроенного сервера строки синхронизации быть не должно")

        addCard(in: app)

        XCTAssertFalse(status.waitForExistence(timeout: 2), "Без настроенного сервера строка не появляется даже с несинхронизированной правкой")
    }

    func testUnreachableServerShowsStatusWithNoCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        // Порт 9 на loopback не слушается: реальный отказ соединения.
        configureServer(in: app, url: "http://127.0.0.1:9", token: "offline-token", expected: "Не удалось связаться")
        restart(app)

        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        assertLabel("Сервер недоступен — повтор при следующем открытии", on: app.staticTexts["syncStatus"])
        attachScreenshot("Пустое обучение — сервер недоступен", in: app)
    }

    func testRejectedTokenOnAutoFetchAndPushIsNotConflict() throws {
        let url = try localServerURL()
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()

        let expected = "Токен отклонён — проверьте настройки сервера"
        configureServer(in: app, url: url, token: "synthetic-invalid-token", expected: "Токен отклонён")
        restart(app)

        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        assertLabel(expected, on: app.staticTexts["syncStatus"])
        attachScreenshot("Пустое обучение — токен отклонён", in: app)

        addCard(in: app)
        let alert = app.alerts["Синхронизация"]
        XCTAssertTrue(alert.staticTexts[expected].waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        assertLabel(expected, on: app.staticTexts["syncStatus"])
    }

    func testConflictSurvivesAlertDismissalAndClearsAfterPull() async throws {
        let url = try localServerURL()
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["KANKI_STATUS_UI_TOKEN"])
        let revision = try await advanceServerRevision(url: url, token: token)
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        configureServer(in: app, url: url, token: token, expected: "Подключено:")
        restart(app)
        let status = app.staticTexts["syncStatus"]
        assertLabel("Синхронизировано, ревизия \(revision)", on: status)

        let remoteRevision = try await advanceServerRevision(url: url, token: token)
        addCard(in: app)
        let alert = app.alerts["Синхронизация"]
        XCTAssertTrue(alert.buttons["OK"].waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()
        assertLabel("Конфликт ревизий — разрешите в настройках", on: status)

        app.tabBars.buttons["Настройки"].tap()
        let pull = app.buttons["serverPull"]
        if !pull.isHittable { app.swipeUp() }
        pull.tap()
        app.buttons["Заменить"].tap()
        assertLabel("Загружено, ревизия \(remoteRevision)", on: app.staticTexts["serverStatus"])
        app.tabBars.buttons["Обучение"].tap()
        XCTAssertTrue(app.staticTexts["Карточек пока нет"].waitForExistence(timeout: 5))
        assertLabel("Синхронизировано, ревизия \(remoteRevision)", on: status)

        addCard(in: app)
        assertLabel("Синхронизировано, ревизия \(remoteRevision + 1)", on: status)
    }

    func testManualPushConflictReachesLearningAndClearsAfterPull() async throws {
        let url = try localServerURL()
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["KANKI_STATUS_UI_TOKEN"])
        let revision = try await advanceServerRevision(url: url, token: token)
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        configureServer(in: app, url: url, token: token, expected: "Подключено:")
        restart(app)
        let status = app.staticTexts["syncStatus"]
        assertLabel("Синхронизировано, ревизия \(revision)", on: status)

        app.tabBars.buttons["Настройки"].tap()
        let remoteRevision = try await advanceServerRevision(url: url, token: token)
        let push = app.buttons["serverPush"]
        if !push.isHittable { app.swipeUp() }
        push.tap()
        assertLabel("Конфликт ревизий: на сервере \(remoteRevision).", on: app.staticTexts["serverStatus"], predicate: "label BEGINSWITH %@")

        app.tabBars.buttons["Обучение"].tap()
        assertLabel("Конфликт ревизий — разрешите в настройках", on: status)
        app.tabBars.buttons["Настройки"].tap()
        let pull = app.buttons["serverPull"]
        if !pull.isHittable { app.swipeUp() }
        pull.tap()
        app.buttons["Заменить"].tap()
        assertLabel("Загружено, ревизия \(remoteRevision)", on: app.staticTexts["serverStatus"])

        app.tabBars.buttons["Обучение"].tap()
        assertLabel("Синхронизировано, ревизия \(remoteRevision)", on: status)
    }

    func testAutomaticFetchReportsLocalWriteFailureUntilSnapshotCanBeSaved() async throws {
        let url = try localServerURL()
        let root = try appContainerRoot()
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["KANKI_STATUS_UI_TOKEN"])
        let revision = try await advanceServerRevision(url: url, token: token)
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        configureServer(in: app, url: url, token: token, expected: "Подключено:")
        restart(app)
        let status = app.staticTexts["syncStatus"]
        assertLabel("Синхронизировано, ревизия \(revision)", on: status)
        addCard(in: app)
        assertLabel("Синхронизировано, ревизия \(revision + 1)", on: status)

        let file = try snapshotFolder(in: root).appending(path: "kanki.sqlite")
        let localData = try snapshotPayload(in: file)
        let original = try XCTUnwrap(String(bytes: localData, encoding: .utf8))
        XCTAssertTrue(original.contains("Synthetic question"))
        let remoteCard = """
            [{"id":"11111111-2222-4333-8444-555555555555","question":"Synthetic remote card","answer":"Synthetic answer",
              "createdAt":"2026-01-01T00:00:00Z"}]
            """
        let remoteRevision = try await advanceServerRevision(url: url, token: token, cards: remoteCard)
        // Abort the real SQLite write without preventing reads or changing the snapshot row.
        let unblock = "DROP TRIGGER IF EXISTS block_snapshot_write"
        addTeardownBlock { try self.executeSQL(unblock, in: file) }
        try executeSQL("""
            CREATE TRIGGER block_snapshot_write BEFORE INSERT ON learning_snapshot
            BEGIN SELECT RAISE(ABORT, 'snapshot write blocked'); END;
            """, in: file)
        reactivate(app)

        assertLabel("Снимок получен, но не сохранён на устройстве", on: status)
        XCTAssertFalse(app.staticTexts["Карточек пока нет"].exists)
        XCTAssertEqual(try snapshotPayload(in: file), localData)

        try executeSQL(unblock, in: file)
        reactivate(app)
        assertLabel("Синхронизировано, ревизия \(remoteRevision)", on: status)
        XCTAssertFalse(app.staticTexts["Карточек пока нет"].exists)
        let savedData = try snapshotPayload(in: file)
        let saved = try XCTUnwrap(String(bytes: savedData, encoding: .utf8))
        XCTAssertTrue(saved.contains("Synthetic remote card"))
        XCTAssertFalse(saved.contains("Synthetic question"))
        restart(app)
        assertLabel("Синхронизировано, ревизия \(remoteRevision)", on: status)
        XCTAssertEqual(try snapshotPayload(in: file), savedData)
    }

    func testCorruptLegacyRequiresConfirmedPull() async throws {
        let url = try localServerURL()
        let root = try appContainerRoot()
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["KANKI_STATUS_UI_TOKEN"])
        let revision = try await advanceServerRevision(url: url, token: token)
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store", "--reset-server"]
        app.launch()
        configureServer(in: app, url: url, token: token, expected: "Подключено:")
        restart(app)
        let status = app.staticTexts["syncStatus"]
        assertLabel("Синхронизировано, ревизия \(revision)", on: status)
        app.terminate()

        let folder = try snapshotFolder(in: root)
        let file = folder.appending(path: "kanki.sqlite")
        let legacy = folder.appending(path: "cards.json")
        let original = Data([0xff, 0x00, 0x7b])
        try FileManager.default.removeItem(at: file)
        try original.write(to: legacy)
        app.launchArguments = ["-serverHasUnsyncedChanges", "YES"]
        app.launch()
        let paused = "Синхронизация приостановлена: не удалось прочитать карточки"
        assertLabel(paused, on: status)
        let (_, serverRevision) = try await readServerRevision(url: url, token: token)
        XCTAssertEqual(serverRevision, revision, "Corrupt is not an empty snapshot to push")

        let remoteRevision = try await advanceServerRevision(url: url, token: token, cards: """
            [{"id":"11111111-2222-4333-8444-555555555555","question":"Recovered from server","answer":"Synthetic answer",
              "createdAt":"2026-01-01T00:00:00Z"}]
            """)
        restart(app)
        assertLabel(paused, on: status)
        XCTAssertTrue(app.buttons["Повторить чтение"].exists)
        XCTAssertFalse(app.staticTexts["Карточек пока нет"].exists)
        XCTAssertThrowsError(try snapshotPayload(in: file))
        XCTAssertEqual(try Data(contentsOf: legacy), original)

        app.tabBars.buttons["Настройки"].tap()
        let pull = app.buttons["serverPull"]
        if !pull.isHittable { app.swipeUp() }
        pull.tap()
        app.buttons["Заменить"].tap()
        assertLabel("Загружено, ревизия \(remoteRevision)", on: app.staticTexts["serverStatus"])
        restart(app)
        assertLabel("Синхронизировано, ревизия \(remoteRevision)", on: status)
        let saved = try XCTUnwrap(String(bytes: snapshotPayload(in: file), encoding: .utf8))
        XCTAssertTrue(saved.contains("Recovered from server"))
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        let (_, finalRevision) = try await readServerRevision(url: url, token: token)
        XCTAssertEqual(finalRevision, remoteRevision)
    }

    private func appContainerRoot() throws -> String {
        try XCTUnwrap(
            ProcessInfo.processInfo.environment["KANKI_STATUS_UI_APP_CONTAINER_ROOT"],
            "Передайте родительскую папку контейнера отдельного симулятора без клонирования"
        )
    }

    // Передайте родительскую папку `simctl get_app_container <id> app.kanki.ios data`:
    // Xcode может переустановить приложение и изменить UUID контейнера перед тестом.
    private func snapshotFolder(in root: String) throws -> URL {
        let containers = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: root, isDirectory: true),
            includingPropertiesForKeys: nil
        )
        let matches = containers.filter { container in
            let metadata = container.appending(path: ".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: metadata),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return false
            }
            return values["MCMMetadataIdentifier"] as? String == "app.kanki.ios"
        }
        let container = try XCTUnwrap(matches.count == 1 ? matches.first : nil, "Ожидается один контейнер приложения")
        return container.appending(path: "Library/Application Support/Kanki")
    }

    private func reactivate(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        app.activate()
    }

    // Opt-in: только одноразовая локальная БД, никаких внешних URL.
    private func localServerURL() throws -> String {
        guard let rawPort = ProcessInfo.processInfo.environment["KANKI_STATUS_UI_PORT"] else {
            throw XCTSkip("Задайте KANKI_STATUS_UI_PORT и KANKI_STATUS_UI_TOKEN для одноразового сервера")
        }
        let port = try XCTUnwrap(UInt16(rawPort))
        return "http://127.0.0.1:\(port)"
    }

    // Второй клиент меняет ревизию настоящего сервера, не локальный снимок приложения.
    private func advanceServerRevision(url: String, token: String, cards: String = "[]") async throws -> Int {
        let (getRequest, revision) = try await readServerRevision(url: url, token: token)
        var request = getRequest
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"base_revision":\#(revision),"data":{"cards":\#(cards)}}"#.utf8)
        let (_, putResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((putResponse as? HTTPURLResponse)?.statusCode, 200)
        return revision + 1
    }

    private func readServerRevision(url: String, token: String) async throws -> (URLRequest, Int) {
        let endpoint = try XCTUnwrap(URL(string: "\(url)/v1/snapshot"))
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (request, try XCTUnwrap(snapshot?["revision"] as? Int))
    }

    private func addCard(in app: XCUIApplication) {
        app.buttons["addSessionCard"].tap()
        let question = app.descendants(matching: .any)["cardQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("Synthetic question")
        let answer = app.descendants(matching: .any)["cardAnswer"]
        answer.tap()
        answer.typeText("Synthetic answer")
        app.buttons["Добавить"].tap()
    }

    private func configureServer(in app: XCUIApplication, url: String, token: String, expected: String) {
        app.tabBars.buttons["Настройки"].tap()
        let serverURL = app.textFields["serverURL"]
        XCTAssertTrue(serverURL.waitForExistence(timeout: 10))
        serverURL.tap()
        serverURL.typeText(url)
        let serverToken = app.secureTextFields["serverToken"]
        serverToken.tap()
        serverToken.typeText(token)
        app.buttons["serverCheck"].tap()
        assertLabel(expected, on: app.staticTexts["serverStatus"], predicate: "label BEGINSWITH %@")
    }

    private func restart(_ app: XCUIApplication) {
        app.launchArguments = []
        app.terminate()
        app.launch()
    }

    private func assertLabel(_ text: String, on element: XCUIElement, predicate: String = "label == %@") {
        expectation(for: NSPredicate(format: predicate, text), evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension SyncStatusUITests {
    private func snapshotPayload(in file: URL) throws -> Data {
        try withDatabase(at: file, flags: SQLITE_OPEN_READONLY) { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let query = "SELECT payload FROM learning_snapshot WHERE id = 1"
            try requireSQLite(sqlite3_prepare_v2(db, query, -1, &statement, nil), equals: SQLITE_OK, in: db)
            try requireSQLite(sqlite3_step(statement), equals: SQLITE_ROW, in: db)
            let bytes = try XCTUnwrap(sqlite3_column_blob(statement, 0))
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        }
    }

    private func executeSQL(_ sql: String, in file: URL) throws {
        try withDatabase(at: file, flags: SQLITE_OPEN_READWRITE) { db in
            try requireSQLite(sqlite3_exec(db, sql, nil, nil, nil), equals: SQLITE_OK, in: db)
        }
    }

    private func withDatabase<T>(at file: URL, flags: Int32, _ read: (OpaquePointer) throws -> T) throws -> T {
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(file.path, &connection, flags, nil)
        defer { sqlite3_close(connection) }
        let db = try XCTUnwrap(connection)
        try requireSQLite(result, equals: SQLITE_OK, in: db)
        try requireSQLite(sqlite3_busy_timeout(db, 5_000), equals: SQLITE_OK, in: db)
        return try read(db)
    }

    private func requireSQLite(_ result: Int32, equals expected: Int32, in db: OpaquePointer) throws {
        guard result == expected else {
            throw NSError(domain: "SQLite", code: Int(result), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }
}
