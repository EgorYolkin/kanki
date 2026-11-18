import Foundation
import GRDB
import XCTest

@testable import Kanki

final class DeltaStoreTests: XCTestCase {
    private let stream = UUID()
    private let uid = "n-018f3a2b-7c41-7000-8000-000000000001"
    private let otherUID = "n-018f3a2b-7c41-7000-8000-000000000002"
    private let key = AnkiE1Import.CardKey(guid: "synthetic-guid", ord: 0)
    private let reviewedAt = Date(timeIntervalSince1970: 1_800_000_000.125)

    func testRepeatedPullPreservesOfflineScheduleAndOneJournalEntry() throws {
        try withStores { source, peer in
            try LocalCardStore.bindDeltaStream(stream, in: source)
            try LocalCardStore.bindDeltaStream(stream, in: peer)
            let initial = DeltaPage(stream: stream, changes: [publication(seq: 1, title: "A")], more: false)
            XCTAssertEqual(try LocalCardStore.applyDeltaPage(initial, since: .start, in: source), 1)
            let card = try LocalCardStore.importedCard(key, from: source)
            let rated = try LocalCardStore.recordImportedReview(key, shown: card, rating: .good, at: reviewedAt, in: source)
            let pending = try XCTUnwrap(pendingEvents(from: source).compactMap { event -> DeltaReview? in
                if case .review(let review) = event { return review }
                return nil
            }.first)
            let reviewChange = DeltaPage.Change(seq: 3, anchor: UUID(), event: .review(pending))
            let changes = [publication(seq: 2, title: "B"), reviewChange]
            let subsequent = DeltaPage(stream: stream, changes: changes, more: false)
            let initialCursor = try LocalCardStore.deltaCursor(from: source)
            XCTAssertEqual(try LocalCardStore.applyDeltaPage(subsequent, since: initialCursor, in: source), 2)
            XCTAssertEqual(try LocalCardStore.applyDeltaPage(subsequent, since: initialCursor, in: source), 0)
            XCTAssertEqual(try batch(from: source).ids, [pending.id])
            try LocalCardStore.acknowledgeDeltaEvents([pending.id], in: source)
            XCTAssertTrue(try batch(from: source).ids.isEmpty)
            let after = try LocalCardStore.importedCard(key, from: source)
            XCTAssertEqual(after.content.title, "B")
            XCTAssertEqual(after.schedule, rated.schedule)
            XCTAssertEqual(after.reviews, rated.reviews)
            XCTAssertEqual(after.reviews.first?.reviewedAt, reviewedAt)

            // A peer can receive history before it has installed the matching content.
            let orphan = DeltaPage(stream: stream, changes: [reviewChange], more: false)
            _ = try LocalCardStore.applyDeltaPage(orphan, since: .start, in: peer)
            let peerNote = DeltaPage(stream: stream, changes: [publication(seq: 4, title: "B")], more: false)
            _ = try LocalCardStore.applyDeltaPage(peerNote, since: LocalCardStore.deltaCursor(from: peer), in: peer)
            let received = try LocalCardStore.importedCard(key, from: peer)
            XCTAssertEqual(received.reviews.map(\.rating), [.good])
            XCTAssertNil(received.schedule)
            XCTAssertTrue(try batch(from: peer).ids.isEmpty)
        }
    }

    func testAnkiDisagreementPreservesRawUnitsAndDoesNotMakeFSRS() throws {
        try withStores { store, _ in
            try LocalCardStore.bindDeltaStream(stream, in: store)
            let original = progress(seq: 1, due: 18, ivl: 8, queue: -1, reviews: [review(id: 10, ivl: -600)])
            let competing = progress(seq: 3, due: 1_800_000_600, ivl: 0, queue: 1, reviews: [
                review(id: 10, ivl: 6), review(id: 20, ivl: -60)
            ])
            let page = DeltaPage(stream: stream, changes: [original, publication(seq: 2, title: "A"), competing], more: false)
            _ = try LocalCardStore.applyDeltaPage(page, since: .start, in: store)
            let restored = try LocalCardStore.importedCard(key, from: store)
            XCTAssertEqual(restored.ankiProgress?.due, 18)
            XCTAssertEqual(restored.ankiProgress?.ivl, 8)
            XCTAssertEqual(restored.ankiProgress?.reviews, [review(id: 10, ivl: -600), review(id: 20, ivl: -60)])
            XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).progress, 1)
            XCTAssertNil(restored.schedule)
            XCTAssertFalse(restored.canReview(at: reviewedAt))
            XCTAssertTrue(restored.reviews.isEmpty)
        }
    }

    func testOutOfOrderPageRollsBackAndUnrelatedStreamCannotBind() throws {
        try withStores { store, _ in
            try LocalCardStore.bindDeltaStream(stream, in: store)
            XCTAssertThrowsError(try LocalCardStore.bindDeltaStream(UUID(), in: store))
            let page = DeltaPage(stream: stream, changes: [publication(seq: 2, title: "A"), publication(seq: 1, title: "B")], more: false)
            XCTAssertThrowsError(try LocalCardStore.applyDeltaPage(page, since: .start, in: store))
            XCTAssertEqual(try LocalCardStore.deltaCursor(from: store), .start)
            XCTAssertTrue(try LocalCardStore.importedCards(from: store).isEmpty)
        }
    }

    func testDeltaDoesNotOverwriteDivergentLocalPublication() throws {
        try withStores { store, _ in
            try LocalCardStore.bindDeltaStream(stream, in: store)
            let first = DeltaPage(stream: stream, changes: [publication(seq: 1, title: "Сервер")], more: false)
            _ = try LocalCardStore.applyDeltaPage(first, since: .start, in: store)
            try LocalCardStore.mergeAnkiImport(AnkiE1Import.preparePublication(sourceNote(mod: 2, title: "Локальная")), into: store)
            let later = DeltaPage(stream: stream, changes: [publication(seq: 3, title: "Новая публикация")], more: false)
            _ = try LocalCardStore.applyDeltaPage(later, since: LocalCardStore.deltaCursor(from: store), in: store)
            XCTAssertEqual(try LocalCardStore.importedCard(key, from: store).content.title, "Локальная")
            XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).publications, 1)
            XCTAssertEqual(try LocalCardStore.deltaCursor(from: store).seq, 3)
        }
    }

    func testOtherUIDIsQuarantinedWithOrWithoutAnExistingOwner() throws {
        try withStores { first, second in
            for (store, ownerFirst) in [(first, true), (second, false)] {
                let wrongReview = DeltaReview(
                    kind: .review,
                    id: UUID().uuidString.lowercased(),
                    uid: otherUID,
                    guid: key.guid,
                    ord: 0,
                    reviewedAt: reviewedAt.timeIntervalSince1970,
                    rating: .easy
                )
                let wrong = DeltaPage.Change(seq: 2, anchor: UUID(), event: .review(wrongReview))
                let wrongRaw = progress(seq: 3, due: 999, ivl: 70, queue: -1, reviews: [review(id: 22, ivl: 70)], owner: otherUID)
                let correctRaw = progress(seq: 4, due: 18, ivl: 8, queue: 2, reviews: [review(id: 22, ivl: -600)])
                let owner = publication(seq: ownerFirst ? 1 : 5, title: "Владелец")
                var events = [wrong, wrongRaw, correctRaw]
                events.insert(owner, at: ownerFirst ? 0 : events.count)
                events.append(publication(seq: 6, title: "Другой UID", owner: otherUID))
                try LocalCardStore.bindDeltaStream(stream, in: store)
                _ = try LocalCardStore.applyDeltaPage(.init(stream: stream, changes: events, more: false), since: .start, in: store)

                let card = try LocalCardStore.importedCard(key, from: store)
                XCTAssertEqual(card.content.uid, uid)
                XCTAssertEqual(card.ankiProgress?.due, 18)
                XCTAssertEqual(card.ankiProgress?.reviews, [review(id: 22, ivl: -600)])
                XCTAssertTrue(card.reviews.isEmpty)
                XCTAssertNil(card.schedule)
                XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).quarantined, 2)
                XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).publications, 1)
            }
        }
    }

    func testOutboxBoundsEncodedBytesAndRetainsOversizedEvent() throws {
        try withStores { store, _ in
            let oversized = AnkiE1Import.CardKey(guid: String(repeating: "💡", count: 270_000), ord: 0)
            let large = AnkiE1Import.CardKey(guid: String(repeating: "\"é", count: 5_400), ord: 0)
            try LocalCardStore.open(at: store).write { db in
                try LocalCardStore.enqueueAnkiProgress(.init(due: 0, ivl: 0, queue: 0, reviews: []), uid: uid, key: oversized, in: db)
                for i in 1...50 {
                    try LocalCardStore.enqueueAnkiProgress(.init(due: Int64(i), ivl: 1, queue: 2, reviews: []), uid: uid, key: large, in: db)
                }
            }
            let first = try batch(from: store)
            XCTAssertGreaterThan(first.ids.count, 0)
            XCTAssertLessThan(first.ids.count, 50)
            XCTAssertLessThanOrEqual(first.body.count, 1_048_576)
            try LocalCardStore.acknowledgeDeltaEvents(first.ids, in: store)
            let second = try batch(from: store)
            XCTAssertEqual(Set(first.ids + second.ids).count, 50)
            XCTAssertLessThanOrEqual(second.body.count, 1_048_576)
            try LocalCardStore.acknowledgeDeltaEvents(second.ids, in: store)
            XCTAssertTrue(try batch(from: store).ids.isEmpty)
            XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).quarantined, 1)
            let retained = try LocalCardStore.open(at: store).read { db in
                try Data.fetchOne(db, sql: "SELECT payload FROM delta_progress WHERE guid = ?", arguments: [oversized.guid])
            }
            let event = try JSONDecoder().decode(DeltaProgress.self, from: XCTUnwrap(retained))
            XCTAssertEqual(event.guid, oversized.guid)
        }
    }

    func testChangedAnchorDoesNotTreatDifferentPageAsSuccessfulReplay() throws {
        try withStores { store, _ in
            try LocalCardStore.bindDeltaStream(stream, in: store)
            let accepted = DeltaPage(stream: stream, changes: [publication(seq: 1, title: "Принята")], more: false)
            _ = try LocalCardStore.applyDeltaPage(accepted, since: .start, in: store)
            let changed = DeltaPage(stream: stream, changes: [publication(seq: 1, title: "Другая история")], more: false)
            XCTAssertThrowsError(try LocalCardStore.applyDeltaPage(changed, since: .start, in: store))
            XCTAssertEqual(try LocalCardStore.importedCard(key, from: store).content.title, "Принята")
            XCTAssertEqual(try LocalCardStore.deltaCursor(from: store).anchor, accepted.changes.first?.anchor)
        }
    }

    func testMergesIdenticalObservationWithoutDuplicatingReview() {
        let first = AnkiE1Import.Progress(due: 5, ivl: 3, queue: 2, reviews: [review(id: 10, ivl: -600)])
        let (unchanged, conflict) = AnkiE1Import.mergeProgress(first, into: first)
        XCTAssertEqual(unchanged, first)
        XCTAssertFalse(conflict)
    }

    func testLegacyAnkiPackageRawProgressMatchesBackend() throws {
        guard let folder = ProcessInfo.processInfo.environment["KANKI_E6_INPUT_DIR"] else {
            throw XCTSkip("Сгенерируйте два пакета Э6 из experiments/README.md")
        }
        let directory = URL(fileURLWithPath: folder)
        try withStores { sm2Store, fsrsStore in
            for (name, store) in [("sm2", sm2Store), ("fsrs", fsrsStore)] {
                let package = directory.appending(path: "\(name).apkg")
                let fixture = try Data(contentsOf: directory.appending(path: "\(name).json"))
                let expected = try JSONDecoder().decode(AnkiE1Import.Package.self, from: fixture).cards
                XCTAssertEqual(expected.count, 2)
                try LocalCardStore.importAnkiPackage(at: package, into: store)
                try LocalCardStore.importAnkiPackage(at: package, into: store)
                let pending = try pendingEvents(from: store).compactMap { event -> DeltaProgress? in
                    if case .progress(let progress) = event { return progress }
                    return nil
                }
                XCTAssertEqual(pending.count, expected.count)
                for raw in expected {
                    let imported = try LocalCardStore.importedCard(raw.key, from: store)
                    XCTAssertEqual(imported.ankiProgress, raw.progress)
                    XCTAssertEqual(imported.isSuspendedInAnki, raw.progress?.queue == -1)
                    XCTAssertNil(imported.schedule)
                    XCTAssertTrue(imported.reviews.isEmpty)
                    XCTAssertEqual(pending.first { $0.guid == raw.guid && $0.ord == raw.ord }?.progress, raw.progress)
                }
            }
        }
    }

    func testPendingRawProgressWinsBeforePackageOrPublicationCreatesCard() throws {
        guard let folder = ProcessInfo.processInfo.environment["KANKI_E6_INPUT_DIR"] else {
            throw XCTSkip("Сгенерируйте пакеты Э6 из experiments/README.md")
        }
        let directory = URL(fileURLWithPath: folder)
        let raw = try Data(contentsOf: directory.appending(path: "sm2.json"))
        let fixture = try JSONDecoder().decode(AnkiE1Import.Package.self, from: raw)
        let note = try XCTUnwrap(fixture.notes.first)
        let key = AnkiE1Import.CardKey(guid: note.guid, ord: 0)
        let original = try XCTUnwrap(fixture.cards.first { $0.key == key }?.progress)
        let matching = try XCTUnwrap(original.reviews.first)
        let conflicting = review(id: matching.id, ivl: matching.ivl + 1)
        let incoming = DeltaProgress(
            kind: .progress,
            id: UUID().uuidString.lowercased(),
            uid: note.fields[0],
            guid: note.guid,
            ord: 0,
            progress: .init(due: original.due + 1, ivl: original.ivl + 1, queue: original.queue, reviews: [conflicting])
        )
        try withStores { published, imported in
            let page = DeltaPage(stream: stream, changes: [.init(seq: 1, anchor: UUID(), event: .progress(incoming))], more: false)
            for store in [published, imported] {
                try LocalCardStore.bindDeltaStream(stream, in: store)
                _ = try LocalCardStore.applyDeltaPage(page, since: .start, in: store)
            }
            let publication = DeltaPage(stream: stream, changes: [.init(seq: 2, anchor: UUID(), event: .publication(note))], more: false)
            _ = try LocalCardStore.applyDeltaPage(publication, since: LocalCardStore.deltaCursor(from: published), in: published)
            let package = directory.appending(path: "sm2.apkg")
            try LocalCardStore.importAnkiPackage(at: package, into: imported)
            try LocalCardStore.importAnkiPackage(at: package, into: published)
            for store in [published, imported] {
                let detail = try LocalCardStore.importedCard(key, from: store)
                XCTAssertEqual(detail.ankiProgress, incoming.progress)
                XCTAssertNil(detail.schedule)
                XCTAssertTrue(detail.reviews.isEmpty)
                XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).progress, 1)
            }
        }
    }

    private func sourceNote(mod: Int64, title: String, owner: String? = nil, guid: String? = nil) -> AnkiE1Import.SourceNote {
        .init(
            guid: guid ?? key.guid,
            modelID: AnkiE1Import.modelID,
            mod: mod,
            fields: [owner ?? uid, title, "Body", "Question", "Answer", "", "[]", "1"]
        )
    }

    private func publication(seq: Int64, title: String, owner: String? = nil) -> DeltaPage.Change {
        .init(seq: seq, anchor: UUID(), event: .publication(sourceNote(mod: seq, title: title, owner: owner)))
    }

    private func progress(
        seq: Int64, due: Int64, ivl: Int, queue: Int, reviews: [AnkiE1Import.Review], owner: String? = nil
    ) -> DeltaPage.Change {
        let event = DeltaProgress(
            kind: .progress,
            id: UUID().uuidString.lowercased(),
            uid: owner ?? uid,
            guid: key.guid,
            ord: key.ord,
            progress: .init(due: due, ivl: ivl, queue: queue, reviews: reviews)
        )
        return .init(seq: seq, anchor: UUID(), event: .progress(event))
    }

    private func review(id: Int64, ivl: Int) -> AnkiE1Import.Review {
        .init(id: id, ease: 3, ivl: ivl, lastIvl: -60, factor: 2_500, time: 568, type: 0)
    }

    private func batch(from store: URL) throws -> DeltaBatch {
        try LocalCardStore.nextDeltaBatch(
            stream: stream, cursor: LocalCardStore.deltaCursor(from: store), eventLimit: DeltaBatch.eventLimit, from: store
        )
    }

    private func pendingEvents(from store: URL) throws -> [DeltaEvent] {
        struct Body: Decodable { let events: [DeltaEvent] }

        return try JSONDecoder().decode(Body.self, from: batch(from: store).body).events
    }

    private func withStores(_ run: (URL, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try run(folder.appending(path: "source/kanki.sqlite"), folder.appending(path: "peer/kanki.sqlite"))
    }
}
