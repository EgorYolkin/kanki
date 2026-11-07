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
        let url = directory.appending(path: "cards.json")
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
        try Data(json.utf8).write(to: url)

        let snapshot = try LocalCardStore.load(from: url)

        XCTAssertEqual(snapshot.cards.count, 1)
        XCTAssertEqual(snapshot.cards[0].question, "Вопрос")
        XCTAssertNil(snapshot.cards[0].deck, "Старый снимок без категории → «Без категории»")
        XCTAssertFalse(snapshot.cards[0].isArchived, "Старый снимок без архива → карточка активна")
        XCTAssertEqual(snapshot.reviews.first?.rating, .hard)
        XCTAssertEqual(snapshot.snapshotVersion, LearningSnapshot.currentSnapshotVersion)
    }
}
