import Foundation
import GRDB

struct ImportedCardSummary: Identifiable, Decodable, FetchableRecord {
    let guid: String
    let ord: Int
    let title: String

    var id: AnkiE1Import.CardKey { .init(guid: guid, ord: ord) }
}

struct ImportedCardContent: Equatable, Decodable, FetchableRecord {
    let title: String
    let question: String
    let answer: String
    let relations: [AnkiE1Import.Relation]
    let mod: Int64
}

struct ImportedCardReview: Identifiable, Equatable, Decodable, FetchableRecord {
    let id: Int64
    private let timestamp: Double
    let rating: RecallRating

    var reviewedAt: Date { Date(timeIntervalSince1970: timestamp) }

    private enum CodingKeys: String, CodingKey {
        case id, rating
        case timestamp = "reviewedAt"
    }
}

struct ImportedCardDetail: Equatable {
    let content: ImportedCardContent
    let schedule: CardSchedule?
    let reviews: [ImportedCardReview]

    func canReview(at date: Date) -> Bool {
        schedule.map { $0.due <= date } ?? true
    }
}

extension LocalCardStore {
    static func createImportedReviewTables(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE imported_card_schedule (
                guid TEXT NOT NULL,
                ord INTEGER NOT NULL,
                state BLOB NOT NULL,
                PRIMARY KEY (guid, ord),
                FOREIGN KEY (guid, ord) REFERENCES note_cards(guid, ord)
            );
            CREATE TABLE review_log (
                id INTEGER PRIMARY KEY,
                guid TEXT NOT NULL,
                ord INTEGER NOT NULL,
                reviewedAt REAL NOT NULL,
                rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
                FOREIGN KEY (guid, ord) REFERENCES note_cards(guid, ord)
            );
            CREATE INDEX review_log_card ON review_log(guid, ord, id);
            """)
    }

    static func importedCards(from url: URL = fileURL) throws -> [ImportedCardSummary] {
        try open(at: url).read { db in
            try ImportedCardSummary.fetchAll(db, sql: """
                SELECT c.guid, c.ord, n.title FROM note_cards c JOIN notes n ON n.guid = c.guid
                ORDER BY n.title, n.uid, c.ord
                """)
        }
    }

    static func importedCard(_ key: AnkiE1Import.CardKey, from url: URL = fileURL) throws -> ImportedCardDetail {
        try open(at: url).read { db in
            guard let content = try importedContent(key, in: db) else { throw CardReviewError.staleCard }
            return try importedDetail(key, content: content, in: db)
        }
    }

    static func recordImportedReview(
        _ key: AnkiE1Import.CardKey,
        shown detail: ImportedCardDetail,
        rating: RecallRating,
        at date: Date,
        in url: URL = fileURL
    ) throws -> ImportedCardDetail {
        try open(at: url).write { db in
            guard try importedContent(key, in: db) == detail.content,
                  try importedSchedule(key, in: db) == detail.schedule,
                  detail.canReview(at: date) else { throw CardReviewError.staleCard }
            let next = try CardScheduling.nextReview(for: detail.schedule, rating: rating, at: date)
            try db.execute(sql: """
                INSERT INTO imported_card_schedule (guid, ord, state) VALUES (?, ?, ?)
                ON CONFLICT (guid, ord) DO UPDATE SET state = excluded.state
                """, arguments: [key.guid, key.ord, try JSONEncoder().encode(next)])
            try db.execute(sql: """
                INSERT INTO review_log (guid, ord, reviewedAt, rating) VALUES (?, ?, ?, ?)
                """, arguments: [key.guid, key.ord, date.timeIntervalSince1970, rating.rawValue])
            return try importedDetail(key, content: detail.content, in: db, schedule: next)
        }
    }

    private static func importedContent(_ key: AnkiE1Import.CardKey, in db: Database) throws -> ImportedCardContent? {
        let sql = """
            SELECT n.title, n.question, n.answer, n.relations, n.mod FROM note_cards c JOIN notes n ON n.guid = c.guid
            WHERE c.guid = ? AND c.ord = ?
            """
        return try ImportedCardContent.fetchOne(db, sql: sql, arguments: [key.guid, key.ord])
    }

    private static func importedSchedule(_ key: AnkiE1Import.CardKey, in db: Database) throws -> CardSchedule? {
        let sql = """
            SELECT state FROM imported_card_schedule WHERE guid = ? AND ord = ?
            """
        let state = try Data.fetchOne(db, sql: sql, arguments: [key.guid, key.ord])
        return try state.map { try JSONDecoder().decode(CardSchedule.self, from: $0) }
    }

    private static func importedDetail(
        _ key: AnkiE1Import.CardKey,
        content: ImportedCardContent,
        in db: Database,
        schedule: CardSchedule? = nil
    ) throws -> ImportedCardDetail {
        let sql = """
            SELECT id, reviewedAt, rating FROM review_log WHERE guid = ? AND ord = ? ORDER BY id DESC
            """
        return try ImportedCardDetail(
            content: content,
            schedule: schedule ?? importedSchedule(key, in: db),
            reviews: ImportedCardReview.fetchAll(db, sql: sql, arguments: [key.guid, key.ord])
        )
    }
}
