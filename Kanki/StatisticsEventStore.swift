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
            try enqueueActivity(at: Date(timeIntervalSince1970: timestamp), rating: rating, in: db)
        }
    }

    static func enqueueActivity(at date: Date, rating: Int?, in db: Database) throws {
        let raw = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let destination = ServerConfiguration(rawValue: raw)?.displayValue
        let sql = "INSERT INTO statistics_queue (id, timestamp, rating, destination) VALUES (?, ?, ?, ?)"
        try db.execute(sql: sql, arguments: [UUID().uuidString, date.timeIntervalSince1970, rating, destination])
    }

    static func recordVisit(at date: Date, in url: URL = fileURL) throws {
        try open(at: url).write { db in try enqueueActivity(at: date, rating: nil, in: db) }
    }

    static func pendingActivity(for destination: String, in url: URL = fileURL) throws -> [StatisticsEvent] {
        try open(at: url).write { db in
            try db.execute(sql: "UPDATE statistics_queue SET destination = ? WHERE destination IS NULL", arguments: [destination])
            let sql = "SELECT id, timestamp, rating FROM statistics_queue WHERE destination = ? ORDER BY rowid LIMIT 100"
            return try Row.fetchAll(db, sql: sql, arguments: [destination]).map { row in
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
