import Foundation

/// Локальное хранилище демо-данных, пока сервер не подключён.
///
/// JSON-снимок в Application Support — источник истины на устройстве: он небольшой,
/// читается человеком и может быть загружен на сервер, когда появится синхронизация.
/// Каждая запись атомарно заменяет файл; ошибки чтения и записи возвращаются вызывающему.
enum LocalCardStore {
    /// Аргумент запуска для UI-тестов: удаляет снимок до того, как первый экран его прочитает.
    static let resetArgument = "--reset-store"

    private static let folderName = "Kanki"
    private static let fileName = "cards.json"

    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func load() throws -> LearningSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LearningSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LearningSnapshot.self, from: Data(contentsOf: fileURL))
    }

    static func save(_ snapshot: LearningSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
