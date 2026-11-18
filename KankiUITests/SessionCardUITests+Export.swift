import Foundation
import XCTest

extension SessionCardUITests {
    struct ExportedCard: Decodable, Equatable {
        let question: String
        let answer: String
    }

    private struct ExportedArchive: Decodable {
        let formatVersion: Int
        let cards: [ExportedCard]
    }

    func saveExport(in app: XCUIApplication, folder: String) throws -> [ExportedCard] {
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 45), "Системный диалог экспорта не открылся")

        // Оба экспорта предлагают одно имя; сохраняем их в разные новые папки.
        let localTitle = app.navigationBars.staticTexts["On My iPhone"]
        let localLocation = app.staticTexts["On My iPhone"]
        let browse = app.navigationBars.buttons["Browse"]
        let back = app.navigationBars.buttons["On My iPhone"]
        if !localTitle.exists {
            if back.exists {
                back.tap()
            } else {
                if browse.exists {
                    browse.tap()
                }
                XCTAssertTrue(localLocation.waitForExistence(timeout: 5))
                localLocation.tap()
            }
        }
        XCTAssertTrue(localTitle.waitForExistence(timeout: 5))
        let more = app.navigationBars.buttons["More"]
        let newFolder = app.buttons["New Folder"]
        more.tap()
        // При возврате из папки первый тап может попасть на анимацию перехода.
        if !newFolder.waitForExistence(timeout: 3) {
            more.tap()
            XCTAssertTrue(newFolder.waitForExistence(timeout: 5))
        }
        newFolder.tap()
        let name = app.collectionViews.textViews.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let keyboardIntro = app.buttons["Continue"]
        if keyboardIntro.exists && keyboardIntro.isHittable {
            keyboardIntro.tap()
        }
        name.typeText(folder + XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(app.navigationBars.buttons["\(folder), Actions Menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Folder is Empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(name.waitForNonExistence(timeout: 10))

        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 30), "Files не завершил сохранение в \(folder)")
        XCTAssertFalse(app.alerts["Не удалось экспортировать"].exists)
        return try readSavedExport(in: folder)
    }

    private func readSavedExport(in folder: String) throws -> [ExportedCard] {
        // Читаем только архив из уникальной папки этого запуска, не другие документы.
        let resources = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"],
            "Проверка JSON требует локального контейнера iOS Simulator"
        )
        let groups = URL(fileURLWithPath: resources).appending(path: "Containers/Shared/AppGroup")
        let manager = FileManager.default
        let paths = try manager.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil).map {
            $0.appending(path: "File Provider Storage/\(folder)/kanki-cards.json")
        }
        let saved = try XCTUnwrap(paths.first { manager.fileExists(atPath: $0.path) }, "Нет сохранённого JSON в \(folder)")
        let data = try Data(contentsOf: saved)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = folder
        attachment.lifetime = .keepAlways
        add(attachment)
        let archive = try JSONDecoder().decode(ExportedArchive.self, from: data)
        XCTAssertEqual(archive.formatVersion, 1)
        return archive.cards
    }
}
