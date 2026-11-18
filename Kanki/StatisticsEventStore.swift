import Foundation
import GRDB

struct StatisticsEvent: Encodable {
    let id: UUID
    let kind: String
    let timestamp: Date
    let rating: Int?
}

extension LocalCardStore {
    static func createStatisticsQueue(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE statistics_queue (
                id TEXT NOT NULL UNIQUE, timestamp REAL NOT NULL, rating INTEGER, destination TEXT
            );
            """)
        // Каждая уже сохранённая локальная оценка импорта получает постоянный UUID один раз.
        let history = try Row.fetchCursor(db, sql: "SELECT reviewedAt, rating FROM review_log ORDER BY id")
        while let row = try history.next() {
            let timestamp: Double = row["reviewedAt"]
            let rating: Int = row["rating"]
            try db.execute(
                sql: "INSERT INTO statistics_queue (id, timestamp, rating) VALUES (?, ?, ?)",
                arguments: [UUID().uuidString, timestamp, rating]
            )
        }
    }

    static func migrateStatisticsOrigins(in db: Database) throws {
        try db.execute(sql: "CREATE TABLE statistics_verified_origin (origin TEXT NOT NULL)")
        let origins = try String.fetchAll(db, sql: "SELECT DISTINCT destination FROM statistics_queue WHERE destination IS NOT NULL")
        for origin in origins {
            guard let canonical = ServerConfiguration(rawValue: origin)?.displayValue, canonical != origin else { continue }
            try db.execute(sql: "UPDATE statistics_queue SET destination = ? WHERE destination = ?", arguments: [canonical, origin])
        }
    }

    static func enqueueActivity(at date: Date, rating: Int?, in db: Database) throws {
        let sql = """
            INSERT INTO statistics_queue (id, timestamp, rating, destination)
            VALUES (?, ?, ?, (SELECT origin FROM statistics_verified_origin WHERE origin = ?))
            """
        try db.execute(sql: sql, arguments: [UUID().uuidString, date.timeIntervalSince1970, rating, ServerTokenStore.configuration?.displayValue])
    }

    static func recordVisit(at date: Date, in url: URL = fileURL) throws {
        try open(at: url).write { db in try enqueueActivity(at: date, rating: nil, in: db) }
    }

    static func hasUnboundActivity(in url: URL = fileURL) throws -> Bool {
        try open(at: url).read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM statistics_queue WHERE destination IS NULL)") == true
        }
    }

    /// Call only after authenticating the currently committed credentials. A failed
    /// attempt never claims offline history; later retries keep the original IDs.
    static func confirmActivityDestination(_ destination: ServerConfiguration, in url: URL = fileURL) throws {
        try open(at: url).write { db in
            try db.execute(sql: "DELETE FROM statistics_verified_origin")
            try db.execute(sql: "INSERT INTO statistics_verified_origin VALUES (?)", arguments: [destination.displayValue])
            try db.execute(sql: "UPDATE statistics_queue SET destination = ? WHERE destination IS NULL", arguments: [destination.displayValue])
        }
    }

    static func pendingActivity(for destination: ServerConfiguration, in url: URL = fileURL) throws -> [StatisticsEvent] {
        try open(at: url).read { db in
            let sql = "SELECT id, timestamp, rating FROM statistics_queue WHERE destination = ? ORDER BY rowid LIMIT 100"
            return try Row.fetchAll(db, sql: sql, arguments: [destination.displayValue]).map { row in
                let timestamp: Double = row["timestamp"]
                let rating: Int? = row["rating"]
                guard let id = UUID(uuidString: row["id"]) else { throw ServerError.decoding }
                return StatisticsEvent(
                    id: id,
                    kind: rating == nil ? "visit" : "imported_review",
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    rating: rating
                )
            }
        }
    }

    static func acknowledgeActivity(_ batch: [StatisticsEvent], in url: URL = fileURL) throws {
        try open(at: url).write { db in
            for event in batch {
                try db.execute(sql: "DELETE FROM statistics_queue WHERE id = ?", arguments: [event.id.uuidString])
            }
        }
    }
}
