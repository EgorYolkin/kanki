import GRDB
import XCTest

@testable import Kanki

final class ImportedNoteStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testStageFiveDatabaseIsBackfilledWithoutChangingCardsSchedulesOrSnapshot() throws {
        try withStore { url in
            let source = note(
                "n-source",
                title: "Синтетика &amp; оптика",
                body: "<div>Дифракция</div>света<br>интер<strong>ференция</strong>.",
                relations: [.init(kind: .requires, targetUID: "n-missing", note: "Сначала прочитать")]
            )
            let progress = AnkiE1Import.Progress(due: 40, ivl: 2, queue: 2, reviews: [])
            let card = AnkiE1Import.Card(guid: source.guid, ord: 0, progress: progress)
            let snapshot = LearningSnapshot(cards: [SessionCard(question: "Ручная карточка", answer: "Ответ", createdAt: date)])
            let schedule = try CardScheduling.nextReview(for: nil, rating: .good, at: date)
            try createOldDatabase(at: url, note: source, card: card, snapshot: snapshot, schedule: schedule)

            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "ОПТИК", from: url).map(\.title), ["Синтетика & оптика"])
            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "опт—дифракц", from: url).map(\.uid), [source.uid])
            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "свет интерференция", from: url).map(\.uid), [source.uid])
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: "strong", from: url).isEmpty)
            let detail = try XCTUnwrap(LocalCardStore.importedNote(source.uid, from: url))
            XCTAssertEqual(detail.body, "Дифракция света интерференция.")
            XCTAssertEqual(detail.outgoing.first?.uid, "n-missing")
            XCTAssertNil(detail.outgoing.first?.title)
            XCTAssertEqual(detail.outgoing.first?.comment, "Сначала прочитать")
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), .init(notes: [source], cards: [card]))
            let imported = try LocalCardStore.importedCard(card.key, from: url)
            XCTAssertEqual(imported.schedule, schedule)
            XCTAssertEqual(imported.reviews.map(\.rating), [.good])
            XCTAssertEqual(imported.reviews.map(\.reviewedAt), [date])
            XCTAssertEqual(try LocalCardStore.load(from: url), snapshot)
        }
    }

    func testImportSeparatesHTMLBlocksAndBreaksButPreservesInlineWords() throws {
        try withStore { url in
            let source = note("n-source", title: "Оптика", body: "Луч<div>Альфа</div>Бета<br>диф<strong>ракция</strong> света")
            try LocalCardStore.mergeAnkiImport(.init(notes: [source], cards: []), into: url)

            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "опт—дифр", from: url).map(\.uid), [source.uid])
            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "луч альфа бета дифракция", from: url).map(\.uid), [source.uid])
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: "ракция", from: url).isEmpty)
        }
    }

    func testAlreadyIndexedDatabaseRepairsStaleBodyAndSearchTerms() throws {
        try withStore { url in
            let source = note("n-source", title: "Оптика", body: "<div>Альфа</div>Бета")
            try LocalCardStore.mergeAnkiImport(.init(notes: [source], cards: []), into: url)
            try DatabaseQueue(path: url.path).write { db in
                try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'importedNoteBodyBoundaries'")
                try db.execute(sql: "UPDATE note_library SET body = 'АльфаБета' WHERE uid = ?", arguments: [source.uid])
            }

            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "бета", from: url).map(\.uid), [source.uid])
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: "альфабета", from: url).isEmpty)
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url).notes, [source])
        }
    }

    func testMissingTargetResolvesAndReimportReplacesOnlyChangedSearchAndEdges() throws {
        try withStore { url in
            let requires = AnkiE1Import.Relation(kind: .requires, targetUID: "n-target", note: "Эталон")
            let source = note("n-source", title: "Отражение", body: "Старый текст", relations: [requires, requires])
            let target = note("n-target", title: "Преломление", relations: [
                .init(kind: .partOf, targetUID: source.uid, note: nil),
                .init(kind: .related, targetUID: "n-second-hop", note: nil)
            ])
            try LocalCardStore.mergeAnkiImport(.init(notes: [source], cards: []), into: url)
            let missing = try XCTUnwrap(LocalCardStore.importedNote(source.uid, from: url))
            XCTAssertEqual(missing.outgoing.map(\.uid), [target.uid, target.uid])
            XCTAssertEqual(missing.neighbors, [.init(id: target.uid, title: nil, outgoing: true, incoming: false)])
            XCTAssertNil(try LocalCardStore.importedNote(target.uid, from: url))

            try LocalCardStore.mergeAnkiImport(.init(notes: [target], cards: []), into: url)
            let resolved = try XCTUnwrap(LocalCardStore.importedNote(source.uid, from: url))
            XCTAssertEqual(resolved.neighbors, [.init(id: target.uid, title: target.title, outgoing: true, incoming: true)])
            XCTAssertEqual(resolved.backlinks.map(\.type), ["has_part"])
            let neighbor = try XCTUnwrap(LocalCardStore.importedNote(target.uid, from: url))
            XCTAssertEqual(neighbor.backlinks.map(\.type), ["required_for", "required_for"])
            XCTAssertEqual(neighbor.backlinks.map(\.comment), ["Эталон", "Эталон"])

            let changed = note(source.uid, title: "Рассеяние", body: "Новый текст", mod: 2)
            for version in [changed, changed, source] {
                try LocalCardStore.mergeAnkiImport(.init(notes: [version], cards: []), into: url)
            }
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: "старый", from: url).isEmpty)
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: "Отражение", from: url).isEmpty)
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: #"* (:) """#, from: url).isEmpty)
            XCTAssertEqual(try LocalCardStore.importedNotes(matching: "НОВЫЙ", from: url).map(\.uid), [source.uid])
            let refreshed = try XCTUnwrap(LocalCardStore.importedNote(source.uid, from: url))
            XCTAssertEqual(refreshed.neighbors, [.init(id: target.uid, title: target.title, outgoing: false, incoming: true)])
            XCTAssertTrue(try XCTUnwrap(LocalCardStore.importedNote(target.uid, from: url)).backlinks.isEmpty)
        }
    }

    func testFailedBatchRollsBackSearchAndEdgesAlongWithCanonicalNotes() throws {
        try withStore { url in
            let existing = note("n-existing", title: "Призма")
            try LocalCardStore.mergeAnkiImport(.init(notes: [existing], cards: []), into: url)
            let new = note("n-new", title: "Интерференция", relations: [.init(kind: .contrast, targetUID: existing.uid, note: nil)])
            let conflict = note(existing.uid, title: "Другой текст")
            XCTAssertThrowsError(try LocalCardStore.mergeAnkiImport(.init(notes: [new, conflict], cards: []), into: url))
            XCTAssertNil(try LocalCardStore.importedNote(new.uid, from: url))
            XCTAssertTrue(try LocalCardStore.importedNotes(matching: new.title, from: url).isEmpty)
            XCTAssertTrue(try XCTUnwrap(LocalCardStore.importedNote(existing.uid, from: url)).backlinks.isEmpty)
        }
    }

    private func createOldDatabase(
        at url: URL,
        note: AnkiE1Import.Note,
        card: AnkiE1Import.Card,
        snapshot: LearningSnapshot,
        schedule: CardSchedule
    ) throws {
        let queue = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("initialLocalStore") { db in
            try db.execute(sql: "CREATE TABLE learning_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
            try LocalCardStore.createImportTables(in: db)
        }
        migrator.registerMigration("importedCardReview", migrate: LocalCardStore.createImportedReviewTables)
        try migrator.migrate(queue)
        try queue.write { db in
            try note.insert(db)
            try card.insert(db)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try db.execute(sql: "INSERT INTO learning_snapshot VALUES (1, ?)", arguments: [try encoder.encode(snapshot)])
            try db.execute(
                sql: "INSERT INTO imported_card_schedule (guid, ord, state) VALUES (?, ?, ?)",
                arguments: [card.guid, card.ord, try JSONEncoder().encode(schedule)]
            )
            try db.execute(
                sql: "INSERT INTO review_log (guid, ord, reviewedAt, rating) VALUES (?, ?, ?, ?)",
                arguments: [card.guid, card.ord, date.timeIntervalSince1970, RecallRating.good.rawValue]
            )
        }
    }

    private func note(
        _ uid: String,
        title: String,
        body: String = "",
        mod: Int64 = 1,
        relations: [AnkiE1Import.Relation] = []
    ) -> AnkiE1Import.Note {
        .init(
            uid: uid,
            guid: "guid-\(uid)",
            modelID: 1_936_480_171,
            schemaVersion: 1,
            mod: mod,
            title: title,
            body: body,
            question: "",
            answer: "",
            sources: "[]",
            relations: relations
        )
    }

    private func withStore(_ run: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try run(folder.appending(path: "kanki.sqlite"))
    }
}
