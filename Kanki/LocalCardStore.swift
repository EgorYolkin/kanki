import Foundation
import GRDB

/// Продуктовое хранилище ручных карточек и локального импорта. Серверный
/// `LearningSnapshot` остаётся отдельным контрактом, а не схемой этой БД.
enum LocalCardStore {
    /// Аргумент запуска для UI-тестов: удаляет снимок до того, как первый экран его прочитает.
    static let resetArgument = "--reset-store"

    private static let folderName = "Kanki"
    private static let fileName = "kanki.sqlite"
    private static let legacyFileName = "cards.json"

    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func load(from url: URL = fileURL) throws -> LearningSnapshot {
        try open(at: url).read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM learning_snapshot WHERE id = 1") else {
                return LearningSnapshot()
            }
            return try decode(data)
        }
    }

    static func save(_ snapshot: LearningSnapshot, to url: URL = fileURL) throws {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try open(at: url).write { db in
            try writeSnapshot(data, in: db)
        }
    }

    static func open(at url: URL) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        let legacyURL = legacyFile(beside: url)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("initialLocalStore") { db in
            try db.execute(sql: """
                CREATE TABLE learning_snapshot (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    payload BLOB NOT NULL
                );
                """)
            try createImportTables(in: db)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                let data = try Data(contentsOf: legacyURL)
                _ = try decode(data)
                try writeSnapshot(data, in: db)
            }
        }
        try migrator.migrate(queue)
        return queue
    }

    private static func legacyFile(beside url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: legacyFileName)
    }

    private static func decode(_ data: Data) throws -> LearningSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LearningSnapshot.self, from: data)
    }

    private static func writeSnapshot(_ data: Data, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO learning_snapshot (id, payload) VALUES (1, ?)
            ON CONFLICT (id) DO UPDATE SET payload = excluded.payload
            """, arguments: [data])
    }

    static func reset() {
        try? FileManager.default.removeItem(at: legacyFile(beside: fileURL))
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Notification.Name {
    static let kankiSnapshotReloaded = Notification.Name("kanki.snapshotReloaded")
}
