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

    static func load(from url: URL = fileURL) throws -> LearningSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return LearningSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LearningSnapshot.self, from: Data(contentsOf: url))
        let cardIDs = Set(snapshot.cards.map(\.id))
        guard cardIDs.count == snapshot.cards.count,
              snapshot.reviews.allSatisfy({ cardIDs.contains($0.cardID) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return snapshot
    }

    static func save(_ snapshot: LearningSnapshot, to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Notification.Name {
    static let kankiSnapshotReloaded = Notification.Name("kanki.snapshotReloaded")
}
