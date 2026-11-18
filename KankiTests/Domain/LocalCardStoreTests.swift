import XCTest

@testable import Kanki

final class LocalCardStoreTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "kanki-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// Снимок v1 со старого устройства: без `snapshot_version`, `deck`,
    /// `isArchived` и `deck_renames`, даты — ISO-8601, как их пишет стор.
    func testLoadsLegacySnapshotThroughStoreDecoder() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let legacy = directory.appending(path: "cards.json")
        let json = """
        {
          "cards": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "question": "Вопрос",
              "answer": "Ответ",
              "createdAt": "2026-01-02T03:04:05Z"
            }
          ],
          "reviews": [
            {
              "cardID": "11111111-1111-1111-1111-111111111111",
              "rating": 2,
              "reviewedAt": "2026-01-02T04:00:00Z"
            }
          ],
          "schedules": {}
        }
        """
        let bytes = Data(json.utf8)
        try bytes.write(to: legacy)

        let snapshot = try LocalCardStore.load(from: url)

        XCTAssertEqual(snapshot.cards.count, 1)
        XCTAssertEqual(snapshot.cards[0].question, "Вопрос")
        XCTAssertNil(snapshot.cards[0].deck, "Старый снимок без категории → «Без категории»")
        XCTAssertFalse(snapshot.cards[0].isArchived, "Старый снимок без архива → карточка активна")
        XCTAssertEqual(snapshot.reviews.first?.rating, .hard)
        XCTAssertEqual(snapshot.snapshotVersion, LearningSnapshot.currentSnapshotVersion)

        var updated = snapshot
        XCTAssertTrue(updated.updateCard(id: snapshot.cards[0].id, question: "Новый вопрос", answer: "Ответ", deck: nil))
        try LocalCardStore.save(updated, to: url)
        XCTAssertEqual(try LocalCardStore.load(from: url), updated)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
    }

    func testSavingDuplicateCardIDsPreservesExistingSnapshotBytes() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let card = SessionCard(
            id: try XCTUnwrap(UUID(uuidString: "2621F15A-306C-435A-9680-AEEB602F272D")),
            question: "Вопрос",
            answer: "Ответ",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let original = LearningSnapshot(cards: [card])
        try LocalCardStore.save(original, to: url)
        let originalBytes = try Data(contentsOf: url)
        var invalid = original
        invalid.cards.append(card)

        XCTAssertThrowsError(try LocalCardStore.save(invalid, to: url))

        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertEqual(try LocalCardStore.load(from: url), original)
    }

    func testLoadingDuplicateCardIDsRejectsCorruptSnapshot() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let legacy = directory.appending(path: "cards.json")
        let card = """
        {"id":"2621F15A-306C-435A-9680-AEEB602F272D",
        "question":"Вопрос","answer":"Ответ","createdAt":"2026-01-02T03:04:05Z"}
        """
        let payload = Data(#"{"cards":[\#(card),\#(card)]}"#.utf8)
        try payload.write(to: legacy)
        XCTAssertThrowsError(try LocalCardStore.load(from: url))
        XCTAssertEqual(try Data(contentsOf: legacy), payload)
    }

    func testConfirmedPullRecoversBrokenLegacyWithoutChangingItsBytes() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let legacy = directory.appending(path: "cards.json")
        let recovered = makeSnapshot(question: "Снимок с сервера")
        for bytes in [Data([0xff, 0x00, 0x7b]), Data(#"{"snapshot_version":999,"cards":[]}"#.utf8)] {
            try bytes.write(to: legacy)
            XCTAssertThrowsError(try LocalCardStore.load(from: url))
            XCTAssertThrowsError(try LocalCardStore.save(recovered, to: url))

            var invalid = recovered
            invalid.cards.append(contentsOf: recovered.cards)
            XCTAssertThrowsError(try LocalCardStore.replaceFromConfirmedPull(invalid, to: url))
            XCTAssertThrowsError(try LocalCardStore.load(from: url))

            try LocalCardStore.replaceFromConfirmedPull(recovered, to: url)
            XCTAssertEqual(try LocalCardStore.load(from: url), recovered)
            XCTAssertEqual(try Data(contentsOf: legacy), bytes)
            try LocalCardStore.reset(at: url)
        }
    }

    func testFailedMigrationCanRetryWithRepairedLegacy() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let legacy = directory.appending(path: "cards.json")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: false)
        XCTAssertThrowsError(try LocalCardStore.load(from: url))
        try FileManager.default.removeItem(at: legacy)

        let original = makeSnapshot(question: "Исправленный legacy")
        try writeLegacy(original, to: legacy)
        XCTAssertEqual(try LocalCardStore.load(from: url), original)
    }

    func testConcurrentFirstReadsAndWritesPreserveMigration() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let legacy = directory.appending(path: "cards.json")
        let original = makeSnapshot(question: "Старый вопрос")
        let updated = makeSnapshot(question: "Новый вопрос")
        try writeLegacy(original, to: legacy)
        let bytes = try Data(contentsOf: legacy)

        DispatchQueue.concurrentPerform(iterations: 16) { index in
            do {
                if index.isMultiple(of: 2) {
                    let snapshot = try LocalCardStore.load(from: url)
                    XCTAssertTrue(snapshot == original || snapshot == updated)
                } else {
                    try LocalCardStore.save(updated, to: url)
                }
            } catch {
                XCTFail("Concurrent open \(index): \(error)")
            }
        }

        XCTAssertEqual(try LocalCardStore.load(from: url), updated)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
    }

    func testResetClearsActiveStoreAndLegacyWithoutRemovingServerToken() throws {
        let url = directory.appending(path: "kanki.sqlite")
        let legacy = directory.appending(path: "cards.json")
        let token = directory.appending(path: "server-token")
        try writeLegacy(makeSnapshot(question: "Старый вопрос"), to: legacy)
        try LocalCardStore.save(makeSnapshot(question: "Новый вопрос"), to: url)
        let tokenBytes = Data("synthetic-token".utf8)
        try tokenBytes.write(to: token)
        let sidecars = ["-journal", "-wal", "-shm"].map { URL(fileURLWithPath: url.path + $0) }
        for sidecar in sidecars {
            try Data([0x00]).write(to: sidecar)
        }

        try LocalCardStore.reset(at: url)
        try LocalCardStore.reset(at: url)

        for file in [url, legacy] + sidecars {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
        XCTAssertEqual(try Data(contentsOf: token), tokenBytes)
        XCTAssertEqual(try LocalCardStore.load(from: url), LearningSnapshot())
    }

    private func writeLegacy(_ snapshot: LearningSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url)
    }

    private func makeSnapshot(question: String) -> LearningSnapshot {
        LearningSnapshot(cards: [SessionCard(question: question, answer: "Ответ", createdAt: Date(timeIntervalSince1970: 100))])
    }
}
