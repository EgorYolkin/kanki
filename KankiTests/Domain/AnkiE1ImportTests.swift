import Foundation
import XCTest

@testable import Kanki

final class AnkiE1ImportTests: XCTestCase {
    private typealias E1Data = AnkiE1Import

    private let uidA = "n-018f3a2b-7c41-7000-8000-000000000001"
    private let uidB = "n-018f3a2b-7c41-7000-8000-000000000004"
    private let updatedBody = "Обновлённая модель скорости реакции."
    private let modelID: Int64 = 1_936_480_171
    private let fields = ["UID", "Title", "Body", "Question", "Answer", "Relations", "Sources", "SchemaVersion"]

    func testPackageRoundTripThroughProductStore() throws {
        try withStore { url in
            let first = try input("test1", fallback: package())
            let updated = try input("test3", fallback: package(updated: true))
            let reviewed = try input("test2", fallback: package(reviewed: true))
            let incompatible = try input("test4-type-change", fallback: package(model: modelID + 10))
            let snapshot = try makeManualSnapshot()
            try LocalCardStore.save(snapshot, to: url)

            try LocalCardStore.importAnkiE1(content: first, into: url)
            let original = try LocalCardStore.loadAnkiE1(from: url)
            XCTAssertEqual(original.notes.map(\.uid), [uidA, uidB])
            XCTAssertEqual(original.cards.count, 2)
            XCTAssertTrue(original.cards.allSatisfy { $0.progress == nil })
            XCTAssertEqual(original.edges, [edge(uidB, "requires", uidA), edge(uidA, "required_for", uidB, derived: true)])

            try LocalCardStore.importAnkiE1(content: updated, reviewed: reviewed, into: url)
            let restored = try LocalCardStore.loadAnkiE1(from: url)
            try assertRestored(restored, original: original, reviewed: reviewed)
            XCTAssertEqual(try LocalCardStore.load(from: url), snapshot)

            let bytes = try Data(contentsOf: url)
            try LocalCardStore.importAnkiE1(content: updated, reviewed: reviewed, into: url)
            try LocalCardStore.importAnkiE1(content: updated, into: url)
            try LocalCardStore.importAnkiE1(content: first, into: url)
            assertRejected(incompatible, as: .unsupportedNoteType(modelID + 10), in: url)
            try assertRejected(encode(package(version: "2")), as: .unsupportedSchemaVersion(2), in: url)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), restored)
            XCTAssertEqual(try LocalCardStore.load(from: url), snapshot)

            // Ручная правка и подтверждённая загрузка снимка не затрагивают импорт.
            var edited = snapshot
            XCTAssertTrue(edited.updateCard(id: snapshot.cards[0].id, question: "Исправленный вопрос", answer: "Ответ", deck: nil))
            try LocalCardStore.save(edited, to: url)
            XCTAssertEqual(try LocalCardStore.load(from: url), edited)
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), restored)
            try LocalCardStore.replaceFromConfirmedPull(snapshot, to: url)
            XCTAssertEqual(try LocalCardStore.load(from: url), snapshot)
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), restored)
        }
    }

    func testConflictingProgressRollsBackContentUpdate() throws {
        try withStore { url in
            let first = try encode(package())
            try LocalCardStore.importAnkiE1(content: first, reviewed: encode(package(reviewed: true)), into: url)
            let original = try LocalCardStore.loadAnkiE1(from: url)
            let bytes = try Data(contentsOf: url)
            let updated = try encode(package(updated: true))
            let conflicting = try encode(package(reviewed: true, dueA: 1_800_000_700))
            let key = E1Data.CardKey(guid: "guid-A", ord: 0)

            XCTAssertThrowsError(try LocalCardStore.importAnkiE1(content: updated, reviewed: conflicting, into: url)) { error in
                XCTAssertEqual(error as? E1Data.ImportError, .conflictingProgress(key))
            }
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), original)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testRejectsProgressWithSameGUIDButDifferentUID() throws {
        let reviewed = package(reviewed: true)
        let first = reviewed.notes[0]
        var changed = first.fields
        changed[0] = "n-other"
        let wrong = E1Data.SourceNote(guid: first.guid, modelID: first.modelID, mod: first.mod, fields: changed)
        let mixed = E1Data.Package(notes: [wrong, reviewed.notes[1]], models: reviewed.models, cards: reviewed.cards)

        XCTAssertThrowsError(try E1Data.prepare(content: package(), reviewed: mixed)) { error in
            XCTAssertEqual(error as? E1Data.ImportError, .mismatchedProgress)
        }
    }

    func testRejectsFieldReorderingAndDuplicateCardKeys() throws {
        let first = package()
        let wrong = E1Data.Package(notes: first.notes, models: [String(modelID): fields.reversed()], cards: first.cards)
        let duplicates = E1Data.Package(notes: first.notes, models: first.models, cards: [first.cards[0], first.cards[0]])
        XCTAssertThrowsError(try E1Data.prepare(content: wrong, reviewed: nil)) { error in
            XCTAssertEqual(error as? E1Data.ImportError, .unsupportedFieldLayout)
        }
        XCTAssertThrowsError(try E1Data.prepare(content: duplicates, reviewed: nil)) { error in
            XCTAssertEqual(error as? E1Data.ImportError, .invalidCardIdentity(first.cards[0].key))
        }
    }

    func testRejectsStoredIdentityCollisionsAndSameModContentWithoutPartialUpdate() throws {
        try withStore { url in
            let first = package()
            let updated = package(updated: true)
            try LocalCardStore.importAnkiE1(content: encode(first), into: url)
            let original = try LocalCardStore.loadAnkiE1(from: url)
            let bytes = try Data(contentsOf: url)
            let note = first.notes[0]
            var fieldsWithOtherUID = note.fields
            fieldsWithOtherUID[0] = "n-other"
            let collisions: [(E1Data.SourceNote, E1Data.ImportError)] = [
                (.init(guid: "guid-other", modelID: modelID, mod: 2, fields: updated.notes[0].fields), .invalidNoteIdentity(uidA)),
                (.init(guid: note.guid, modelID: modelID, mod: 2, fields: fieldsWithOtherUID), .invalidNoteIdentity("n-other")),
                (.init(guid: note.guid, modelID: modelID, mod: note.mod, fields: updated.notes[0].fields), .conflictingContent(uidA))
            ]

            for (incoming, error) in collisions {
                let card = E1Data.Card(guid: incoming.guid, ord: 0, progress: nil)
                // A valid update precedes each conflict inside the same transaction.
                let conflicting = E1Data.Package(notes: [updated.notes[1], incoming], models: first.models, cards: [first.cards[1], card])
                try assertRejected(encode(conflicting), as: error, in: url)
                XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), original)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }

    func testRejectsNonzeroOrdinalForTheSingleE1TemplateWithoutChangingStore() throws {
        try withStore { url in
            let first = package()
            try LocalCardStore.importAnkiE1(content: encode(first), into: url)
            let bytes = try Data(contentsOf: url)
            let updated = package(updated: true)
            let card = E1Data.Card(guid: updated.notes[0].guid, ord: 1, progress: nil)
            let wrong = E1Data.Package(notes: updated.notes, models: updated.models, cards: [card, updated.cards[1]])

            try assertRejected(encode(wrong), as: .invalidCardIdentity(card.key), in: url)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    private func assertRestored(_ restored: E1Data, original: E1Data, reviewed: Data) throws {
        XCTAssertEqual(restored.notes.map(\.uid), original.notes.map(\.uid))
        XCTAssertEqual(restored.notes.map(\.guid), original.notes.map(\.guid))
        XCTAssertEqual(restored.notes.map(\.modelID), [modelID, modelID])
        XCTAssertEqual(restored.notes.map(\.schemaVersion), [1, 1])
        XCTAssertEqual(restored.notes.first?.body, updatedBody)
        XCTAssertEqual(restored.notes.first?.question, "Что означает Km?")
        XCTAssertEqual(restored.notes.first?.answer, "Концентрация субстрата при половине Vmax.")
        XCTAssertEqual(restored.edges, [
            edge(uidA, "related", uidB), edge(uidB, "related", uidA, derived: true),
            edge(uidB, "requires", uidA), edge(uidA, "required_for", uidB, derived: true)
        ])
        XCTAssertEqual(restored.cards.map(\.key), original.cards.map(\.key))
        let source = try JSONDecoder().decode(E1Data.Package.self, from: reviewed)
        let byKey = Dictionary(uniqueKeysWithValues: source.cards.map { ($0.key, $0.progress) })
        for card in restored.cards {
            let progress = try XCTUnwrap(card.progress)
            XCTAssertEqual(progress, try XCTUnwrap(byKey[card.key]))
            XCTAssertGreaterThan(progress.due, 1_000_000_000)
            XCTAssertEqual(progress.ivl, 0)
            XCTAssertEqual(progress.queue, 1)
            XCTAssertEqual(progress.reviews.map(\.ease), [3])
            XCTAssertEqual(progress.reviews.map(\.ivl), [-600])
        }
    }

    private func assertRejected(_ data: Data, as expected: E1Data.ImportError, in url: URL) {
        XCTAssertThrowsError(try LocalCardStore.importAnkiE1(content: data, into: url)) { error in
            XCTAssertEqual(error as? E1Data.ImportError, expected)
        }
    }

    private func edge(_ from: String, _ type: String, _ to: String, derived: Bool = false) -> E1Data.Edge {
        E1Data.Edge(sourceUID: from, type: type, targetUID: to, sequence: 0, derived: derived)
    }

    private func makeManualSnapshot() throws -> LearningSnapshot {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = SessionCard(id: id, question: "Ручная карточка", answer: "Ответ", createdAt: now)
        var snapshot = LearningSnapshot(cards: [card])
        try CardScheduling.record(card, rating: .good, in: &snapshot, at: now)
        return snapshot
    }

    private func withStore(_ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory.appending(path: "kanki.sqlite"))
    }

    private func input(_ name: String, fallback: @autoclosure () -> E1Data.Package) throws -> Data {
        guard let path = ProcessInfo.processInfo.environment["KANKI_E1_INPUT_DIR"] else { return try encode(fallback()) }
        let url = URL(filePath: path, directoryHint: .isDirectory).appending(path: "\(name).json")
        let data = try Data(contentsOf: url)
        print("E1 package input: \(name).json")
        return data
    }

    private func encode(_ package: E1Data.Package) throws -> Data {
        try JSONEncoder().encode(package)
    }

    private func package(
        updated: Bool = false,
        reviewed: Bool = false,
        model: Int64? = nil,
        version: String = "1",
        dueA: Int64 = 1_800_000_600
    ) -> E1Data.Package {
        let model = model ?? modelID
        let first = E1Data.SourceNote(guid: "guid-A", modelID: model, mod: updated ? 2 : 1, fields: [
            uidA, "Кинетика", updated ? updatedBody : "Модель скорости реакции.",
            "Что означает Km?", "Концентрация субстрата при половине Vmax.",
            updated ? #"{"t":"related","to":"\#(uidB)"}"# : "", "[]", version
        ])
        let second = E1Data.SourceNote(guid: "guid-B", modelID: model, mod: updated ? 2 : 1, fields: [
            uidB, "Ингибиторы", "Конкуренция за активный центр", "Что влияет на Km?", "Ингибитор",
            #"{"t":"requires","to":"\#(uidA)"}"#, "[]", version
        ])
        let progressA = reviewed ? progress(due: dueA, reviewID: 1) : nil
        let progressB = reviewed ? progress(due: 1_800_000_601, reviewID: 2) : nil
        let cardA = E1Data.Card(guid: first.guid, ord: 0, progress: progressA)
        let cardB = E1Data.Card(guid: second.guid, ord: 0, progress: progressB)
        return E1Data.Package(notes: [first, second], models: [String(model): fields], cards: reviewed ? [cardB, cardA] : [cardA, cardB])
    }

    private func progress(due: Int64, reviewID: Int64) -> E1Data.Progress {
        let review = E1Data.Review(id: reviewID, ease: 3, ivl: -600, lastIvl: -60, factor: 0, time: 5, type: 0)
        return E1Data.Progress(due: due, ivl: 0, queue: 1, reviews: [review])
    }
}
