import CryptoKit
import Foundation
import GRDB

extension LocalCardStore {
    static func createDeltaTables(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE delta_review_log (
                id INTEGER PRIMARY KEY,
                eventID TEXT NOT NULL UNIQUE,
                guid TEXT NOT NULL,
                ord INTEGER NOT NULL,
                reviewedAt REAL NOT NULL,
                rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
                pending INTEGER NOT NULL
            );
            INSERT INTO delta_review_log (id, eventID, guid, ord, reviewedAt, rating, pending)
            SELECT id, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' ||
                       substr(hex(randomblob(2)), 2) || '-8' || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))),
                   guid, ord, reviewedAt, rating, 1
            FROM review_log;
            DROP TABLE review_log;
            ALTER TABLE delta_review_log RENAME TO review_log;
            CREATE INDEX review_log_card ON review_log(guid, ord, reviewedAt, id);
            CREATE INDEX review_log_pending ON review_log(id) WHERE pending = 1;
            CREATE TABLE delta_cursor (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                stream TEXT NOT NULL,
                seq INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE delta_progress (
                id TEXT NOT NULL UNIQUE,
                guid TEXT NOT NULL,
                ord INTEGER NOT NULL,
                payload BLOB NOT NULL,
                pending INTEGER NOT NULL,
                applied INTEGER NOT NULL,
                conflict INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX delta_progress_pending ON delta_progress(pending);
            CREATE INDEX delta_progress_card ON delta_progress(guid, ord, applied);
            CREATE TABLE delta_publications (
                uid TEXT NOT NULL PRIMARY KEY,
                base BLOB,
                candidate BLOB
            );
            """)
        for card in try AnkiE1Import.Card.filter(Column("progress") != nil).fetchAll(db) {
            if let progress = card.progress {
                try enqueueAnkiProgress(progress, key: card.key, in: db)
            }
        }
    }

    static func deltaID() -> String { UUID().uuidString.lowercased() }

    static func deltaCursor(from url: URL) throws -> Int64 {
        try open(at: url).read { try deltaCursor(in: $0) }
    }

    static func bindDeltaStream(_ stream: UUID, in url: URL) throws {
        try open(at: url).write { db in
            try db.execute(sql: "INSERT INTO delta_cursor (id, stream) VALUES (1, ?) ON CONFLICT DO NOTHING", arguments: [stream.uuidString])
            try requireStream(stream, in: db)
        }
    }

    static func pendingDeltaEvents(from url: URL) throws -> [any FetchableDeltaEvent] {
        try open(at: url).read { db in
            let reviews = try DeltaReview.fetchAll(db, sql: """
                SELECT 'review' AS kind, eventID AS id, guid, ord, reviewedAt, rating
                FROM review_log WHERE pending = 1 ORDER BY id LIMIT 50
                """)
            let progressSQL = "SELECT payload FROM delta_progress WHERE pending = 1 ORDER BY rowid LIMIT ?"
            let progress = try Data.fetchAll(db, sql: progressSQL, arguments: [50 - reviews.count])
            var events: [any FetchableDeltaEvent] = reviews
            let decoder = JSONDecoder()
            for payload in progress {
                events.append(try decoder.decode(DeltaProgress.self, from: payload))
            }
            return events
        }
    }

    static func acknowledgeDeltaEvents(_ ids: [String], in url: URL) throws {
        try open(at: url).write { db in
            for id in ids {
                try db.execute(sql: "UPDATE review_log SET pending = 0 WHERE eventID = ? AND pending = 1", arguments: [id])
                try db.execute(sql: "UPDATE delta_progress SET pending = 0 WHERE id = ? AND pending = 1", arguments: [id])
            }
        }
    }

    /// Changes and their cursor commit together; overlapping or interrupted pulls are safe to repeat.
    static func applyDeltaPage(_ page: DeltaPage, since: Int64, in url: URL) throws -> Int {
        try open(at: url).write { db in
            try requireStream(page.stream, in: db)
            let current = try deltaCursor(in: db)
            let end = page.changes.last?.seq ?? since
            if current > since, current >= end { return 0 }
            guard current == since, !page.more || !page.changes.isEmpty else { throw DeltaError.invalidPage }

            var previous = since
            for change in page.changes {
                guard change.seq > previous else { throw DeltaError.invalidPage }
                switch change.event {
                case .publication(let source):
                    try applyDeltaPublication(AnkiE1Import.preparePublication(source), in: db)
                case .review(let review):
                    try applyDeltaReview(review, in: db)
                case .progress(let event):
                    try applyDeltaProgress(event, in: db)
                }
                previous = change.seq
            }
            try db.execute(sql: "UPDATE delta_cursor SET seq = ? WHERE id = 1", arguments: [end])
            return page.changes.count
        }
    }

    static func deltaConflicts(from url: URL) throws -> (progress: Int, publications: Int) {
        try open(at: url).read { db in
            let progress = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (SELECT DISTINCT guid, ord FROM delta_progress WHERE conflict = 1)
                """) ?? 0
            let publications = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM delta_publications WHERE candidate IS NOT NULL") ?? 0
            return (progress, publications)
        }
    }

    private static func applyDeltaPublication(_ batch: AnkiE1Import, in db: Database) throws {
        guard let note = batch.notes.first else { throw DeltaError.invalidPage }

        let baseline = try Data.fetchOne(db, sql: "SELECT base FROM delta_publications WHERE uid = ? AND base IS NOT NULL", arguments: [note.uid])
        let base = try baseline.map { try JSONDecoder().decode(AnkiE1Import.Note.self, from: $0) }
        let current = try AnkiE1Import.Note.fetchOne(db, key: note.uid)
        let owner = try AnkiE1Import.Note.fetchOne(db, key: ["guid": note.guid])
        let payload = try JSONEncoder().encode(note)
        let safeIdentity = (current == nil || current?.guid == note.guid) && (owner == nil || owner?.uid == note.uid)
        let advancesBase = current == base && (current.map { note.mod > $0.mod } ?? true)
        if safeIdentity, current == note || advancesBase {
            try mergeAnkiImport(batch, in: db)
            try db.execute(sql: """
                INSERT INTO delta_publications (uid, base) VALUES (?, ?)
                ON CONFLICT (uid) DO UPDATE SET base = excluded.base, candidate = NULL
                """, arguments: [note.uid, payload])
        } else {
            try db.execute(sql: """
                INSERT INTO delta_publications (uid, candidate) VALUES (?, ?)
                ON CONFLICT (uid) DO UPDATE SET candidate = excluded.candidate
                """, arguments: [note.uid, payload])
        }
    }

    static func enqueueAnkiProgress(_ progress: AnkiE1Import.Progress, key: AnkiE1Import.CardKey, in db: Database) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for start in stride(from: 0, to: max(1, progress.reviews.count), by: 100) {
            let chunk = AnkiE1Import.Progress(
                due: progress.due,
                ivl: progress.ivl,
                queue: progress.queue,
                reviews: Array(progress.reviews[start..<min(start + 100, progress.reviews.count)])
            )
            let payload = DeltaProgress(kind: .progress, id: "", guid: key.guid, ord: key.ord, progress: chunk)
            let digest = SHA256.hash(data: try encoder.encode(payload))
            let bytes = Array(digest.prefix(16))
            let id = UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 0x0f) | 0x40, bytes[7],
                (bytes[8] & 0x3f) | 0x80, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
            let event = DeltaProgress(kind: .progress, id: id.uuidString.lowercased(), guid: key.guid, ord: key.ord, progress: chunk)
            try applyDeltaProgress(event, pending: true, in: db)
        }
    }

    static func applyWaitingAnkiProgress(to key: AnkiE1Import.CardKey, in db: Database) throws {
        let sql = "SELECT payload FROM delta_progress WHERE guid = ? AND ord = ? AND applied = 0 ORDER BY rowid"
        let payloads = try Data.fetchAll(db, sql: sql, arguments: [key.guid, key.ord])
        let decoder = JSONDecoder()
        for payload in payloads {
            try adoptDeltaProgress(decoder.decode(DeltaProgress.self, from: payload), in: db)
        }
    }

    private static func deltaCursor(in db: Database) throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT seq FROM delta_cursor WHERE id = 1") ?? 0
    }

    private static func requireStream(_ stream: UUID, in db: Database) throws {
        guard try String.fetchOne(db, sql: "SELECT stream FROM delta_cursor WHERE id = 1") == stream.uuidString else {
            throw DeltaError.wrongStream
        }
    }

    private static func applyDeltaReview(_ review: DeltaReview, in db: Database) throws {
        // Reviews for cards a peer has not imported yet stay in the same journal.
        let sql = "SELECT 'review' AS kind, eventID AS id, guid, ord, reviewedAt, rating FROM review_log WHERE eventID = ?"
        let stored = try DeltaReview.fetchOne(db, sql: sql, arguments: [review.id])
        if let stored {
            guard stored == review else { throw DeltaError.eventCollision }
            return
        }
        try db.execute(sql: """
            INSERT INTO review_log (eventID, guid, ord, reviewedAt, rating, pending) VALUES (?, ?, ?, ?, ?, 0)
            """, arguments: [review.id, review.guid, review.ord, review.reviewedAt, review.rating.rawValue])
    }

    private static func applyDeltaProgress(_ event: DeltaProgress, pending: Bool = false, in db: Database) throws {
        if let payload = try Data.fetchOne(db, sql: "SELECT payload FROM delta_progress WHERE id = ?", arguments: [event.id]) {
            guard try JSONDecoder().decode(DeltaProgress.self, from: payload) == event else { throw DeltaError.eventCollision }
            return
        }
        try db.execute(sql: """
            INSERT INTO delta_progress (id, guid, ord, payload, pending, applied) VALUES (?, ?, ?, ?, ?, 0)
            """, arguments: [event.id, event.guid, event.ord, try JSONEncoder().encode(event), pending])
        try adoptDeltaProgress(event, in: db)
    }

    private static func adoptDeltaProgress(_ event: DeltaProgress, in db: Database) throws {
        guard let card = try AnkiE1Import.Card.fetchOne(db, key: ["guid": event.guid, "ord": event.ord]) else { return }
        let (merged, conflict) = AnkiE1Import.mergeProgress(event.progress, into: card.progress)
        if merged != card.progress {
            let updated = AnkiE1Import.Card(guid: card.guid, ord: card.ord, progress: merged)
            try updated.update(db)
        }
        try db.execute(sql: "UPDATE delta_progress SET applied = 1, conflict = ? WHERE id = ?", arguments: [conflict, event.id])
    }
}

extension DeltaReview: FetchableRecord {}
