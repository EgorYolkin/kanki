import Foundation
import GRDB

extension LocalCardStore {
    /// Контент и необязательный прогресс получены из раздельных входов Э1.
    static func importAnkiE1(content: Data, reviewed: Data? = nil, into url: URL = fileURL) throws {
        let decoder = JSONDecoder()
        let batch = try AnkiE1Import.prepare(
            content: decoder.decode(AnkiE1Import.Package.self, from: content),
            reviewed: reviewed.map { try decoder.decode(AnkiE1Import.Package.self, from: $0) }
        )
        try mergeAnkiImport(batch, into: url)
    }

    static func mergeAnkiImport(_ batch: AnkiE1Import, into url: URL, preserveProgressConflicts: Bool = false) throws {
        try open(at: url).write { db in
            try mergeAnkiImport(batch, in: db, preserveProgressConflicts: preserveProgressConflicts)
        }
    }

    static func mergeAnkiImport(_ batch: AnkiE1Import, in db: Database, preserveProgressConflicts: Bool = false) throws {
        for note in batch.notes {
            try merge(note, in: db)
        }
        for card in batch.cards {
            if preserveProgressConflicts {
                _ = try merge(.init(guid: card.guid, ord: card.ord, progress: nil), in: db)
                if let progress = card.progress {
                    try enqueueAnkiProgress(progress, key: card.key, in: db)
                }
            } else if try merge(card, in: db), let progress = card.progress {
                try enqueueAnkiProgress(progress, key: card.key, in: db)
            }
            try applyWaitingAnkiProgress(to: card.key, in: db)
        }
    }

    static func loadAnkiE1(from url: URL = fileURL) throws -> AnkiE1Import {
        try open(at: url).read { db in
            try AnkiE1Import(
                notes: AnkiE1Import.Note.order(Column("uid")).fetchAll(db),
                cards: AnkiE1Import.Card.order(Column("guid"), Column("ord")).fetchAll(db)
            )
        }
    }

    static func createImportTables(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE notes (
                uid TEXT NOT NULL PRIMARY KEY,
                guid TEXT NOT NULL UNIQUE,
                modelID INTEGER NOT NULL,
                schemaVersion INTEGER NOT NULL,
                mod INTEGER NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                question TEXT NOT NULL,
                answer TEXT NOT NULL,
                sources TEXT NOT NULL,
                relations TEXT NOT NULL
            );
            CREATE TABLE note_cards (
                guid TEXT NOT NULL REFERENCES notes(guid),
                ord INTEGER NOT NULL,
                progress TEXT,
                PRIMARY KEY (guid, ord)
            );
            """)
    }

    private static func merge(_ note: AnkiE1Import.Note, in db: Database) throws {
        if let current = try AnkiE1Import.Note.fetchOne(db, key: note.uid) {
            if try AnkiE1Import.shouldUpdate(note, replacing: current) {
                try note.update(db)
            }
        } else {
            guard try !AnkiE1Import.Note.exists(db, key: ["guid": note.guid]) else {
                throw AnkiE1Import.ImportError.invalidNoteIdentity(note.uid)
            }
            try note.insert(db)
        }
    }

    private static func merge(_ card: AnkiE1Import.Card, in db: Database) throws -> Bool {
        if let current = try AnkiE1Import.Card.fetchOne(db, key: ["guid": card.guid, "ord": card.ord]) {
            guard try AnkiE1Import.shouldUpdate(card, replacing: current) else { return false }

            try card.update(db)
        } else {
            try card.insert(db)
        }
        return true
    }
}

extension AnkiE1Import.Note: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"
}

extension AnkiE1Import.Card: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_cards"
}
