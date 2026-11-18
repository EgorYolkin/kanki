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

    private struct FilesLabels {
        let localLocation: String
        let browse: String
        let newFolder: String
        let keyboardContinue: String
        let actionsMenu: String
        let emptyFolder: String

        static func forSystemLanguage() throws -> Self {
            // The Files picker is localized by iOS, independently of Kanki's Russian UI.
            let language = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
            switch language {
            case "en":
                return Self(
                    localLocation: "On My iPhone",
                    browse: "Browse",
                    newFolder: "New Folder",
                    keyboardContinue: "Continue",
                    actionsMenu: "Actions Menu",
                    emptyFolder: "Folder is Empty"
                )
            case "ru":
                return Self(
                    localLocation: "На\u{00A0}iPhone",
                    browse: "Обзор",
                    newFolder: "Новая папка",
                    keyboardContinue: "Продолжить",
                    actionsMenu: "Меню действий",
                    emptyFolder: "Папка пуста"
                )
            default:
                throw UnsupportedFilesLanguage(language: language)
            }
        }
    }

    private struct UnsupportedFilesLanguage: LocalizedError {
        let language: String?

        var errorDescription: String? {
            "Нет подписей Files для системного языка \(language ?? "unknown"); используйте ru или en"
        }
    }

    func saveExport(in app: XCUIApplication, folder: String) throws -> [ExportedCard] {
        let labels = try FilesLabels.forSystemLanguage()
        let save = app.buttons.matching(identifier: "DOCPicker.actionButton").element
        XCTAssertTrue(save.waitForExistence(timeout: 45), "Системный диалог экспорта не открылся: \(app.debugDescription)")

        // Оба экспорта предлагают одно имя; сохраняем их в разные новые папки.
        let localRoot = app.otherElements.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage,"
        )).element
        let browse = app.navigationBars.buttons[labels.browse]
        if !localRoot.exists {
            if browse.exists {
                browse.tap()
            }
            let localLocation = app.staticTexts[labels.localLocation]
            XCTAssertTrue(localLocation.waitForExistence(timeout: 5), app.debugDescription)
            localLocation.tap()
        }
        XCTAssertTrue(localRoot.waitForExistence(timeout: 5), app.debugDescription)

        // Files оставляет корневой контейнер в AX-дереве и внутри вложенных папок.
        // В корне кнопка «назад» ведёт к «Обзору», а не к родительской папке.
        let back = localRoot.navigationBars.buttons.matching(identifier: "BackButton").element
        for _ in 0..<5 {
            if browse.exists && browse.isHittable { break }
            XCTAssertTrue(back.exists, app.debugDescription)
            back.tap()
        }
        XCTAssertTrue(browse.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(browse.isHittable, app.debugDescription)

        let more = app.navigationBars.buttons.matching(identifier: "TopOverflowBarButtonItem").element
        let newFolder = app.buttons[labels.newFolder]
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
        more.tap()
        // При возврате из папки первый тап может попасть на анимацию перехода.
        if !newFolder.waitForExistence(timeout: 3) {
            more.tap()
            XCTAssertTrue(newFolder.waitForExistence(timeout: 5), app.debugDescription)
        }
        newFolder.tap()
        let name = app.collectionViews.textViews.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let keyboardIntro = app.buttons[labels.keyboardContinue]
        if keyboardIntro.exists && keyboardIntro.isHittable {
            keyboardIntro.tap()
        }
        name.typeText(folder + XCUIKeyboardKey.return.rawValue)
        let title = app.navigationBars.buttons["\(folder), \(labels.actionsMenu)"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts[labels.emptyFolder].waitForExistence(timeout: 10), app.debugDescription)
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
