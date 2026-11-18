import Foundation
import GRDB
import SwiftSoup

extension LocalCardStore {
    private static let noteTokenizer = FTS5TokenizerDescriptor.unicode61()

    static func createNoteNavigationIndex(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE note_library (
                id INTEGER PRIMARY KEY,
                uid TEXT NOT NULL UNIQUE REFERENCES notes(uid) ON DELETE CASCADE,
                title TEXT NOT NULL,
                body TEXT NOT NULL
            );
            CREATE INDEX note_library_by_title ON note_library(title COLLATE NOCASE, uid);
            CREATE TABLE note_edges (
                sourceUID TEXT NOT NULL REFERENCES notes(uid) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                targetUID TEXT NOT NULL,
                kind TEXT NOT NULL,
                comment TEXT,
                PRIMARY KEY (sourceUID, position)
            );
            CREATE INDEX note_edges_by_target ON note_edges(targetUID, sourceUID, position);
            """)
        // Only the canonical edge has a row. Its target need not be present.
        let notes = try AnkiE1Import.Note.fetchCursor(db)
        while let note = try notes.next() {
            try indexImportedNote(note, in: db)
        }
        try db.create(virtualTable: "note_fts", using: FTS5()) { definition in
            definition.tokenizer = noteTokenizer
            definition.synchronize(withTable: "note_library")
            definition.column("title")
            definition.column("body")
        }
    }

    static func refreshNoteLibraryBodies(in db: Database) throws {
        let notes = try Row.fetchCursor(db, sql: "SELECT uid, body FROM notes")
        while let note = try notes.next() {
            let uid: String = note["uid"]
            let body = try AnkiFieldText.body(note["body"])
            try db.execute(sql: "UPDATE note_library SET body = ? WHERE uid = ? AND body != ?", arguments: [body, uid, body])
        }
    }

    /// Called in the same transaction as a change to the canonical note.
    static func indexImportedNote(_ note: AnkiE1Import.Note, in db: Database) throws {
        let title = AnkiFieldText.title(note.title)
        let body = try AnkiFieldText.body(note.body)
        try db.execute(sql: """
            INSERT INTO note_library (uid, title, body) VALUES (?, ?, ?)
            ON CONFLICT(uid) DO UPDATE SET title = excluded.title, body = excluded.body
            WHERE title != excluded.title OR body != excluded.body
            """, arguments: [note.uid, title, body])
        try db.execute(sql: "DELETE FROM note_edges WHERE sourceUID = ?", arguments: [note.uid])
        for (position, relation) in note.relations.enumerated() {
            try db.execute(sql: """
                INSERT INTO note_edges (sourceUID, position, targetUID, kind, comment)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [note.uid, position, relation.targetUID, relation.kind.rawValue, relation.note])
        }
    }

    static func importedNotes(matching query: String = "", from url: URL = fileURL) throws -> [ImportedNoteSummary] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try open(at: url).read { db in
            if query.isEmpty {
                return try ImportedNoteSummary.fetchAll(db, sql: """
                    SELECT uid, title FROM note_library ORDER BY title COLLATE NOCASE, uid
                    """)
            }
            let tokens = try db.makeTokenizer(noteTokenizer).tokenize(query: query)
            guard !tokens.isEmpty else { return [] }
            let prefixes = tokens.map { token in
                "\"\(token.token.replacingOccurrences(of: "\"", with: "\"\""))\"*"
            }

            let sql = """
                SELECT note_library.uid, note_library.title
                FROM note_fts JOIN note_library ON note_library.id = note_fts.rowid
                WHERE note_fts MATCH ?
                ORDER BY bm25(note_fts, 4.0, 1.0), note_library.title COLLATE NOCASE, note_library.uid
                """
            return try ImportedNoteSummary.fetchAll(db, sql: sql, arguments: [prefixes.joined(separator: " ")])
        }
    }

    static func importedNote(_ uid: String, from url: URL = fileURL) throws -> ImportedNote? {
        try open(at: url).read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT title, body FROM note_library WHERE uid = ?", arguments: [uid]) else {
                return nil
            }

            let outgoingSQL = """
                SELECT e.*, e.targetUID AS neighborUID, n.title
                FROM note_edges e LEFT JOIN note_library n ON n.uid = e.targetUID
                WHERE e.sourceUID = ? ORDER BY e.position
                """
            let backlinksSQL = """
                SELECT e.*, e.sourceUID AS neighborUID, n.title
                FROM note_edges e JOIN note_library n ON n.uid = e.sourceUID
                WHERE e.targetUID = ? ORDER BY e.sourceUID, e.position
                """
            let outgoing = try IndexedNoteEdge.fetchAll(db, sql: outgoingSQL, arguments: [uid])
            let backlinks = try IndexedNoteEdge.fetchAll(db, sql: backlinksSQL, arguments: [uid])
            return ImportedNote(
                summary: ImportedNoteSummary(uid: uid, title: row["title"]),
                body: row["body"],
                outgoing: outgoing.map { $0.link(isBacklink: false) },
                backlinks: backlinks.map { $0.link(isBacklink: true) }
            )
        }
    }
}

extension ImportedNoteSummary: FetchableRecord {}

private struct IndexedNoteEdge: Decodable, FetchableRecord {
    let sourceUID: String
    let position: Int
    let neighborUID: String
    let title: String?
    let kind: AnkiE1Import.RelationKind
    let comment: String?

    func link(isBacklink: Bool) -> ImportedNoteLink {
        ImportedNoteLink(
            id: .init(sourceUID: sourceUID, position: position),
            uid: neighborUID,
            title: title,
            kind: kind,
            comment: comment,
            isBacklink: isBacklink
        )
    }
}

enum AnkiFieldText {
    static func title(_ value: String) -> String {
        // Title is escaped plain text, not an HTML fragment.
        (try? Entities.unescape(value)) ?? value
    }

    static func body(_ value: String) throws -> String {
        let body = try SwiftSoup.parseBodyFragment(value).body()
        let text = NoteBodyText()
        try NodeTraversor(text).traverse(body)
        return text.value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private final class NoteBodyText: NodeVisitor {
    // Default HTML block, list and table boundaries, independent of parser flags or author CSS.
    private static let blockBoundaries: Set<String> = [
        "address", "article", "aside", "blockquote", "caption", "center", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "hgroup", "hr", "legend", "li", "listing", "main", "menu", "nav", "ol",
        "p", "plaintext", "pre", "search", "section", "summary", "table", "tbody", "td", "tfoot",
        "th", "thead", "tr", "ul", "xmp"
    ]

    private(set) var value = ""

    func head(_ node: Node, _ depth: Int) {
        if let text = node as? TextNode {
            value.append(text.getWholeText())
        } else if let element = node as? Element {
            let tag = element.tagNameNormal()
            if tag == "br" || Self.blockBoundaries.contains(tag) {
                value.append(" ")
            }
        }
    }

    func tail(_ node: Node, _ depth: Int) {
        if let element = node as? Element, Self.blockBoundaries.contains(element.tagNameNormal()) {
            value.append(" ")
        }
    }
}
