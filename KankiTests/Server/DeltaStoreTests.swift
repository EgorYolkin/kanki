import Foundation
import XCTest

@testable import Kanki

final class DeltaStoreTests: XCTestCase {
    private let stream = UUID()
    private let uid = "n-018f3a2b-7c41-7000-8000-000000000001"
    private let key = AnkiE1Import.CardKey(guid: "synthetic-guid", ord: 0)
    private let reviewedAt = Date(timeIntervalSince1970: 1_800_000_000.125)

    func testRepeatedPullPreservesOfflineScheduleAndOneJournalEntry() throws {
        try withStores { source, peer in
            try LocalCardStore.bindDeltaStream(stream, in: source)
            try LocalCardStore.bindDeltaStream(stream, in: peer)
            let initial = DeltaPage(stream: stream, changes: [publication(seq: 1, title: "A")], more: false)
            XCTAssertEqual(try LocalCardStore.applyDeltaPage(initial, since: 0, in: source), 1)
            let card = try LocalCardStore.importedCard(key, from: source)
            let rated = try LocalCardStore.recordImportedReview(key, shown: card, rating: .good, at: reviewedAt, in: source)
            let pending = try XCTUnwrap(LocalCardStore.pendingDeltaEvents(from: source).first as? DeltaReview)
            let changes = [publication(seq: 2, title: "B"), .init(seq: 3, event: .review(pending))]
            let subsequent = DeltaPage(stream: stream, changes: changes, more: false)
            XCTAssertEqual(try LocalCardStore.applyDeltaPage(subsequent, since: 1, in: source), 2)
            XCTAssertEqual(try LocalCardStore.applyDeltaPage(subsequent, since: 1, in: source), 0)
            XCTAssertEqual(try LocalCardStore.pendingDeltaEvents(from: source).map(\.id), [pending.id])
            try LocalCardStore.acknowledgeDeltaEvents([pending.id], in: source)
            XCTAssertTrue(try LocalCardStore.pendingDeltaEvents(from: source).isEmpty)
            let after = try LocalCardStore.importedCard(key, from: source)
            XCTAssertEqual(after.content.title, "B")
            XCTAssertEqual(after.schedule, rated.schedule)
            XCTAssertEqual(after.reviews, rated.reviews)
            XCTAssertEqual(after.reviews.first?.reviewedAt, reviewedAt)

            // A peer can receive history before it has installed the matching content.
            let orphan = DeltaPage(stream: stream, changes: [.init(seq: 3, event: .review(pending))], more: false)
            _ = try LocalCardStore.applyDeltaPage(orphan, since: 0, in: peer)
            let peerNote = DeltaPage(stream: stream, changes: [publication(seq: 4, title: "B")], more: false)
            _ = try LocalCardStore.applyDeltaPage(peerNote, since: 3, in: peer)
            let received = try LocalCardStore.importedCard(key, from: peer)
            XCTAssertEqual(received.reviews.map(\.rating), [.good])
            XCTAssertNil(received.schedule)
            XCTAssertTrue(try LocalCardStore.pendingDeltaEvents(from: peer).isEmpty)
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
            _ = try LocalCardStore.applyDeltaPage(page, since: 0, in: store)
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
            XCTAssertThrowsError(try LocalCardStore.applyDeltaPage(page, since: 0, in: store))
            XCTAssertEqual(try LocalCardStore.deltaCursor(from: store), 0)
            XCTAssertTrue(try LocalCardStore.importedCards(from: store).isEmpty)
        }
    }

    func testDeltaDoesNotOverwriteDivergentLocalPublication() throws {
        try withStores { store, _ in
            try LocalCardStore.bindDeltaStream(stream, in: store)
            let first = DeltaPage(stream: stream, changes: [publication(seq: 1, title: "Сервер")], more: false)
            _ = try LocalCardStore.applyDeltaPage(first, since: 0, in: store)
            try LocalCardStore.mergeAnkiImport(AnkiE1Import.preparePublication(sourceNote(mod: 2, title: "Локальная")), into: store)
            let later = DeltaPage(stream: stream, changes: [publication(seq: 3, title: "Новая публикация")], more: false)
            _ = try LocalCardStore.applyDeltaPage(later, since: 1, in: store)
            XCTAssertEqual(try LocalCardStore.importedCard(key, from: store).content.title, "Локальная")
            XCTAssertEqual(try LocalCardStore.deltaConflicts(from: store).publications, 1)
            XCTAssertEqual(try LocalCardStore.deltaCursor(from: store), 3)
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
                let pending = try LocalCardStore.pendingDeltaEvents(from: store).compactMap { $0 as? DeltaProgress }
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

    private func sourceNote(mod: Int64, title: String) -> AnkiE1Import.SourceNote {
        .init(guid: key.guid, modelID: AnkiE1Import.modelID, mod: mod, fields: [uid, title, "Body", "Question", "Answer", "", "[]", "1"])
    }

    private func publication(seq: Int64, title: String) -> DeltaPage.Change {
        .init(seq: seq, event: .publication(sourceNote(mod: seq, title: title)))
    }

    private func progress(seq: Int64, due: Int64, ivl: Int, queue: Int, reviews: [AnkiE1Import.Review]) -> DeltaPage.Change {
        let event = DeltaProgress(
            kind: .progress,
            id: UUID().uuidString.lowercased(),
            guid: key.guid,
            ord: key.ord,
            progress: .init(due: due, ivl: ivl, queue: queue, reviews: reviews)
        )
        return .init(seq: seq, event: .progress(event))
    }

    private func review(id: Int64, ivl: Int) -> AnkiE1Import.Review {
        .init(id: id, ease: 3, ivl: ivl, lastIvl: -60, factor: 2_500, time: 568, type: 0)
    }

    private func withStores(_ run: (URL, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try run(folder.appending(path: "source/kanki.sqlite"), folder.appending(path: "peer/kanki.sqlite"))
    }
}
