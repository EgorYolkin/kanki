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
    private static let initialMigration = "initialLocalStore"
    private static let migrationLock = NSLock()

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
        let data = try encode(snapshot)
        try open(at: url).write { db in
            try writeSnapshot(data, in: db)
        }
    }

    /// Only for a confirmed manual pull. Leave the original legacy file untouched,
    /// even when it cannot be read or decoded.
    static func replaceFromConfirmedPull(_ snapshot: LearningSnapshot, to url: URL = fileURL) throws {
        try open(at: url, replacingWith: encode(snapshot))
    }

    private static func encode(_ snapshot: LearningSnapshot) throws -> Data {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func open(at url: URL) throws -> DatabaseQueue {
        try open(at: url, replacingWith: nil)
    }

    @discardableResult
    private static func open(at url: URL, replacingWith replacement: Data?) throws -> DatabaseQueue {
        // GRDB reads the applied migration list before beginning the migration transaction.
        migrationLock.lock()
        defer { migrationLock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        let legacyURL = legacyFile(beside: url)
        var migrator = DatabaseMigrator()
        migrator.registerMigration(initialMigration) { db in
            try db.execute(sql: """
                CREATE TABLE learning_snapshot (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    payload BLOB NOT NULL
                );
                """)
            try createImportTables(in: db)
            if let data = try replacement ?? readLegacy(at: legacyURL) {
                try writeSnapshot(data, in: db)
            }
        }
        migrator.registerMigration("importedCardReview", migrate: createImportedReviewTables)
        migrator.registerMigration("importedCardDelta", migrate: createDeltaTables)
        let alreadyInitialized = try replacement != nil && queue.read {
            try migrator.appliedIdentifiers($0).contains(initialMigration)
        }
        try migrator.migrate(queue)
        if let replacement, alreadyInitialized {
            try queue.write { db in
                try writeSnapshot(replacement, in: db)
            }
        }
        return queue
    }

    private static func legacyFile(beside url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: legacyFileName)
    }

    private static func readLegacy(at url: URL) throws -> Data? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        _ = try decode(data)
        return data
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

    /// Launch-only UI test hook, before any database connection is opened.
    static func reset(at url: URL = fileURL) throws {
        // Remove legacy first, so a fresh database cannot reimport the test fixture.
        try removeIfPresent(legacyFile(beside: url))
        try removeIfPresent(url)
        for suffix in ["-journal", "-wal", "-shm"] {
            try removeIfPresent(URL(fileURLWithPath: url.path + suffix))
        }
    }

    private static func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

extension Notification.Name {
    static let kankiSnapshotReloaded = Notification.Name("kanki.snapshotReloaded")
}
