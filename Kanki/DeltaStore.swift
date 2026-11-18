import CryptoKit
import Foundation
import GRDB

struct DeltaConflicts {
    let progress: Int
    let publications: Int
    let quarantined: Int
}

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
    }

    static func identifyDeltaEvents(in db: Database) throws {
        // Pending rows originate here. Old received/acknowledged rows have no provable UID.
        try db.execute(sql: """
            ALTER TABLE review_log ADD COLUMN uid TEXT;
            ALTER TABLE delta_progress ADD COLUMN uid TEXT;
            ALTER TABLE delta_cursor ADD COLUMN anchor TEXT;
            UPDATE review_log SET uid = (SELECT uid FROM notes WHERE notes.guid = review_log.guid) WHERE pending = 1;
            """)
        let legacy = try Row.fetchAll(db, sql: """
            SELECT p.id, p.guid, p.ord, p.payload, n.uid
            FROM delta_progress p JOIN notes n ON n.guid = p.guid WHERE p.pending = 1
            """)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for row in legacy {
            struct LegacyPayload: Decodable { let progress: AnkiE1Import.Progress }

            let event = DeltaProgress(
                kind: .progress,
                id: row["id"],
                uid: row["uid"],
                guid: row["guid"],
                ord: row["ord"],
                progress: try decoder.decode(LegacyPayload.self, from: row["payload"]).progress
            )
            try db.execute(sql: "UPDATE delta_progress SET uid = ?, payload = ? WHERE id = ?",
                           arguments: [event.uid, try encoder.encode(event), event.id])
        }
        // Preserve the old aggregate, but do not use it to decide which review or due belonged to this UID.
        try db.execute(sql: """
            CREATE TABLE delta_legacy_anki (
                guid TEXT NOT NULL, ord INTEGER NOT NULL, progress BLOB NOT NULL, PRIMARY KEY (guid, ord)
            );
            INSERT INTO delta_legacy_anki (guid, ord, progress)
            SELECT guid, ord, progress FROM note_cards WHERE progress IS NOT NULL AND EXISTS (
                SELECT 1 FROM delta_progress p
                WHERE p.guid = note_cards.guid AND p.ord = note_cards.ord AND p.uid IS NULL AND p.applied = 1
            );
            UPDATE note_cards SET progress = NULL WHERE (guid, ord) IN (SELECT guid, ord FROM delta_legacy_anki);
            UPDATE delta_progress SET applied = 0, conflict = 0
            WHERE uid IS NOT NULL AND (guid, ord) IN (SELECT guid, ord FROM delta_legacy_anki);
            """)
        for row in try Row.fetchAll(db, sql: "SELECT guid, ord FROM delta_legacy_anki ORDER BY guid, ord") {
            let key = AnkiE1Import.CardKey(guid: row["guid"], ord: row["ord"])
            if let uid = try deltaUID(for: key.guid, in: db) {
                try applyWaitingAnkiProgress(to: key, uid: uid, in: db)
            }
        }
        if try Row.fetchOne(db, sql: "SELECT 1 FROM delta_cursor UNION ALL SELECT 1 FROM delta_progress LIMIT 1") == nil {
            let cards = try AnkiE1Import.Card.fetchAll(db, sql: "SELECT * FROM note_cards WHERE progress IS NOT NULL")
            for card in cards {
                if let progress = card.progress, let uid = try deltaUID(for: card.guid, in: db) {
                    try enqueueAnkiProgress(progress, uid: uid, key: card.key, in: db)
                }
            }
        }
    }

    static func deltaID() -> String { UUID().uuidString.lowercased() }

    static func deltaCursor(from url: URL) throws -> DeltaCursor {
        try open(at: url).read { try deltaCursor(in: $0) }
    }

    static func bindDeltaStream(_ stream: UUID, in url: URL) throws {
        try open(at: url).write { db in
            try db.execute(sql: "INSERT INTO delta_cursor (id, stream) VALUES (1, ?) ON CONFLICT DO NOTHING", arguments: [stream.uuidString])
            try requireStream(stream, in: db)
        }
    }

    static func nextDeltaBatch(
        stream: UUID, cursor: DeltaCursor, eventLimit: Int, from url: URL
    ) throws -> DeltaBatch {
        try open(at: url).write { db in
            let reviews = try DeltaReview.fetchCursor(db, sql: """
                SELECT 'review' AS kind, eventID AS id, uid, guid, ord, reviewedAt, rating
                FROM review_log WHERE pending = 1 AND uid IS NOT NULL ORDER BY id
                """)
            var batch = DeltaBatch(stream: stream, cursor: cursor, eventLimit: eventLimit)
            let encoder = JSONEncoder()
            var rejected: [String] = []
            while batch.ids.count < eventLimit, let review = try reviews.next() {
                guard DeltaIdentity.isValidUID(review.uid), review.reviewedAt.isFinite else {
                    rejected.append(review.id)
                    continue
                }
                if !batch.append(try encoder.encode(review), id: review.id) {
                    if !batch.ids.isEmpty { break }
                    rejected.append(review.id)
                }
            }
            if batch.ids.count < eventLimit {
                let sql = """
                    SELECT id, uid, CASE WHEN length(payload) <= ? THEN payload END AS body
                    FROM delta_progress WHERE pending = 1 AND uid IS NOT NULL ORDER BY rowid
                    """
                let rows = try Row.fetchCursor(db, sql: sql, arguments: [DeltaBatch.byteLimit])
                while batch.ids.count < eventLimit, let row = try rows.next() {
                    let id: String = row["id"]
                    guard DeltaIdentity.isValidUID(row["uid"]) else {
                        rejected.append(id)
                        continue
                    }
                    let body: Data? = row["body"]
                    if let body, batch.append(body, id: id) { continue }
                    if !batch.ids.isEmpty { break }
                    rejected.append(id)
                }
            }
            for id in rejected {
                try quarantineDeltaEvent(id, in: db)
            }
            batch.finish()
            return batch
        }
    }

    static func quarantineDeltaEvent(_ id: String, in url: URL) throws {
        try open(at: url).write { try quarantineDeltaEvent(id, in: $0) }
    }

    private static func quarantineDeltaEvent(_ id: String, in db: Database) throws {
        try db.execute(sql: "UPDATE review_log SET pending = 2 WHERE eventID = ? AND pending = 1", arguments: [id])
        try db.execute(sql: "UPDATE delta_progress SET pending = 2 WHERE id = ? AND pending = 1", arguments: [id])
    }

    static func acknowledgeDeltaEvents(_ ids: [String], in url: URL) throws {
        try open(at: url).write { db in
            for id in ids {
                try db.execute(sql: "UPDATE review_log SET pending = 0 WHERE eventID = ? AND pending = 1", arguments: [id])
                try db.execute(sql: "UPDATE delta_progress SET pending = 0 WHERE id = ? AND pending = 1", arguments: [id])
            }
        }
    }

    /// Changes and their checkpoint commit together; replay of the same page is idempotent.
    static func applyDeltaPage(_ page: DeltaPage, since: DeltaCursor, in url: URL) throws -> Int {
        try open(at: url).write { db in
            try requireStream(page.stream, in: db)
            let current = try deltaCursor(in: db)
            let last = page.changes.last
            let end = last.map { DeltaCursor(seq: $0.seq, anchor: $0.anchor) } ?? since
            if current == end, current != since { return 0 }
            guard current == since, !page.more || last != nil else { throw DeltaError.invalidPage }

            var previous = since.seq
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
            try db.execute(sql: "UPDATE delta_cursor SET seq = ?, anchor = ? WHERE id = 1",
                           arguments: [end.seq, end.anchor?.uuidString])
            return page.changes.count
        }
    }

    static func deltaConflicts(from url: URL) throws -> DeltaConflicts {
        try open(at: url).read { db in
            let progress = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (SELECT DISTINCT uid, guid, ord FROM delta_progress WHERE uid IS NOT NULL AND conflict = 1)
                """) ?? 0
            let publications = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM delta_publications WHERE candidate IS NOT NULL") ?? 0
            let quarantined = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT uid, guid, pending FROM review_log
                    UNION ALL SELECT uid, guid, pending FROM delta_progress
                ) AS event WHERE pending = 2 OR uid IS NULL OR EXISTS (
                    SELECT 1 FROM notes
                    WHERE (notes.guid = event.guid AND notes.uid <> event.uid)
                       OR (notes.uid = event.uid AND notes.guid <> event.guid)
                )
                """) ?? 0
            return DeltaConflicts(progress: progress, publications: publications, quarantined: quarantined)
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

    static func enqueueAnkiProgress(_ progress: AnkiE1Import.Progress, uid: String, key: AnkiE1Import.CardKey, in db: Database) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for start in stride(from: 0, to: max(1, progress.reviews.count), by: 100) {
            let chunk = AnkiE1Import.Progress(
                due: progress.due,
                ivl: progress.ivl,
                queue: progress.queue,
                reviews: Array(progress.reviews[start..<min(start + 100, progress.reviews.count)])
            )
            let payload = DeltaProgress(kind: .progress, id: "", uid: uid, guid: key.guid, ord: key.ord, progress: chunk)
            let digest = SHA256.hash(data: try encoder.encode(payload))
            let bytes = Array(digest.prefix(16))
            let id = UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 0x0f) | 0x40, bytes[7],
                (bytes[8] & 0x3f) | 0x80, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
            let event = DeltaProgress(kind: .progress, id: id.uuidString.lowercased(), uid: uid, guid: key.guid, ord: key.ord, progress: chunk)
            try applyDeltaProgress(event, pending: true, in: db)
        }
    }

    static func applyWaitingAnkiProgress(to key: AnkiE1Import.CardKey, uid: String, in db: Database) throws {
        let sql = "SELECT payload FROM delta_progress WHERE guid = ? AND ord = ? AND uid = ? AND applied = 0 ORDER BY rowid"
        let payloads = try Data.fetchAll(db, sql: sql, arguments: [key.guid, key.ord, uid])
        let decoder = JSONDecoder()
        for payload in payloads {
            try adoptDeltaProgress(decoder.decode(DeltaProgress.self, from: payload), in: db)
        }
    }

    static func deltaUID(for guid: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT uid FROM notes WHERE guid = ?", arguments: [guid])
    }

    private static func deltaCursor(in db: Database) throws -> DeltaCursor {
        guard let row = try Row.fetchOne(db, sql: "SELECT seq, anchor FROM delta_cursor WHERE id = 1") else { return .start }

        let seq: Int64 = row["seq"]
        let value: String? = row["anchor"]
        let anchor = value.flatMap { UUID(uuidString: $0) }
        guard seq == 0 || anchor != nil else { throw DeltaError.unverifiedCursor }
        return DeltaCursor(seq: seq, anchor: anchor)
    }

    private static func requireStream(_ stream: UUID, in db: Database) throws {
        guard try String.fetchOne(db, sql: "SELECT stream FROM delta_cursor WHERE id = 1") == stream.uuidString else {
            throw DeltaError.wrongStream
        }
    }

    private static func applyDeltaReview(_ review: DeltaReview, in db: Database) throws {
        // Reviews for cards a peer has not imported yet stay in the same journal.
        let sql = "SELECT 'review' AS kind, eventID AS id, uid, guid, ord, reviewedAt, rating FROM review_log WHERE eventID = ?"
        let stored = try DeltaReview.fetchOne(db, sql: sql, arguments: [review.id])
        if let stored {
            guard stored == review else { throw DeltaError.eventCollision }
            return
        }
        try db.execute(sql: """
            INSERT INTO review_log (eventID, uid, guid, ord, reviewedAt, rating, pending) VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: [review.id, review.uid, review.guid, review.ord, review.reviewedAt, review.rating.rawValue])
    }

    private static func applyDeltaProgress(_ event: DeltaProgress, pending: Bool = false, in db: Database) throws {
        if let payload = try Data.fetchOne(db, sql: "SELECT payload FROM delta_progress WHERE id = ?", arguments: [event.id]) {
            guard try JSONDecoder().decode(DeltaProgress.self, from: payload) == event else { throw DeltaError.eventCollision }
            return
        }
        try db.execute(sql: """
            INSERT INTO delta_progress (id, uid, guid, ord, payload, pending, applied) VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: [event.id, event.uid, event.guid, event.ord, try JSONEncoder().encode(event), pending])
        try adoptDeltaProgress(event, in: db)
    }

    private static func adoptDeltaProgress(_ event: DeltaProgress, in db: Database) throws {
        guard try deltaUID(for: event.guid, in: db) == event.uid,
              let card = try AnkiE1Import.Card.fetchOne(db, key: ["guid": event.guid, "ord": event.ord]) else { return }
        let (merged, conflict) = AnkiE1Import.mergeProgress(event.progress, into: card.progress)
        if merged != card.progress {
            let updated = AnkiE1Import.Card(guid: card.guid, ord: card.ord, progress: merged)
            try updated.update(db)
        }
        try db.execute(sql: "UPDATE delta_progress SET applied = 1, conflict = ? WHERE id = ?", arguments: [conflict, event.id])
    }
}

extension DeltaReview: FetchableRecord {}
