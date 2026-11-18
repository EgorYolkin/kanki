import Foundation
import XCTest

@MainActor
final class ImportedNoteRefreshUITests: XCTestCase {
    private let sourceUID = "n-018f3a2b-7c41-7000-8000-000000000004"
    private let targetUID = "n-018f3a2b-7c41-7000-8000-000000000001"

    func testOpenLibraryRefreshesActiveSearchAfterCommit() throws {
        let (app, inbox) = try launch(on: "Заметки")
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Menten")
        XCTAssertTrue(app.staticTexts["Ничего не найдено"].waitForExistence(timeout: 5))

        try stage("refresh-target", in: inbox)

        let target = element("libraryNote-\(targetUID)", in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        XCTAssertEqual(search.value as? String, "Menten")
    }

    func testOpenNoteResolvesMissingLinkAfterCommit() throws {
        let (app, inbox) = try launch(on: "Заметки")
        openSource(in: app)
        let missing = element("missingNote-\(targetUID)-0", in: app)
        XCTAssertTrue(missing.waitForExistence(timeout: 5))

        try stage("refresh-target", in: inbox)

        let link = element("outgoing-\(targetUID)-0", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        XCTAssertFalse(missing.exists)
        link.tap()
        assertTargetOpened(in: app)
    }

    func testOpenGraphResolvesMissingNodeAfterCommit() throws {
        let (app, inbox) = try launch(on: "Граф")
        openSource(in: app)
        let missing = element("graphMissing-\(targetUID)", in: app)
        XCTAssertTrue(missing.waitForExistence(timeout: 5))

        try stage("refresh-target", in: inbox)

        let node = element("graphNode-\(targetUID)", in: app)
        XCTAssertTrue(node.waitForExistence(timeout: 8))
        XCTAssertFalse(missing.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Open graph after the target import commits"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        node.tap()
        assertTargetOpened(in: app)
    }

    private func launch(on tab: String) throws -> (XCUIApplication, URL) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let run = UUID().uuidString
        app.launchEnvironment["KANKI_UI_IMPORT_RUN"] = run
        app.launchArguments = ["--reset-store", "--reset-server", "-showNotesSection", "YES", "-showGraphSection", "YES"]
        app.launch()
        // The first launch after installation may replace the app's data container.
        let directory = try importDirectory()
        let inbox = directory.appending(path: "\(run)-pending.apkg")
        try stage("refresh-source", in: inbox)
        let processing = directory.appending(path: "\(run)-importing.apkg")
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: inbox.path) && !FileManager.default.fileExists(atPath: processing.path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 10), .completed, "Начальный пакет не импортирован")
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
        XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
        return (app, inbox)
    }

    private func openSource(in app: XCUIApplication) {
        let source = element("libraryNote-\(sourceUID)", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        source.tap()
    }

    private func assertTargetOpened(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Синтетика Menten"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("backlink-\(sourceUID)-0", in: app).exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func stage(_ fixture: String, in inbox: URL) throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: fixture, withExtension: "apkg"))
        try FileManager.default.createDirectory(at: inbox.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: source).write(to: inbox, options: .atomic)
    }

    private func importDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        let containers = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let appContainer = containers.first { url in
            let metadata = url.appending(path: ".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: metadata),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return false
            }
            return values["MCMMetadataIdentifier"] as? String == "app.kanki.ios"
        }
        return try XCTUnwrap(appContainer).appending(path: "Library/Application Support/Kanki")
    }
}
