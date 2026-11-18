import XCTest

@testable import Kanki

final class ImportedCardStoreTests: XCTestCase {
    func testOfflineReviewSurvivesReopenReimportAndSnapshotPullWithoutChangingAnkiProgress() throws {
        try withStore { url in
            let first = try fixture("test1")
            let updated = try fixture("test3")
            try LocalCardStore.importAnkiPackage(at: first, into: url)
            let batch = try LocalCardStore.loadAnkiE1(from: url)
            let card = try XCTUnwrap(batch.cards.first)
            let raw = AnkiE1Import.Progress(due: 1_800_000_600, ivl: 0, queue: 1, reviews: [
                .init(id: 1, ease: 3, ivl: -600, lastIvl: -60, factor: 0, time: 5, type: 0)
            ])
            let withProgress = AnkiE1Import.Card(guid: card.guid, ord: card.ord, progress: raw)
            try LocalCardStore.mergeAnkiImport(.init(notes: [], cards: [withProgress]), into: url)

            let date = Date(timeIntervalSince1970: 1_800_001_000)
            let manual = SessionCard(question: "Ручной вопрос", answer: "Ручной ответ", createdAt: date)
            var snapshot = LearningSnapshot(cards: [manual])
            try CardScheduling.record(manual, rating: .hard, in: &snapshot, at: date)
            try LocalCardStore.save(snapshot, to: url)
            let before = try LocalCardStore.importedCard(card.key, from: url)
            XCTAssertNil(before.schedule)
            XCTAssertTrue(before.reviews.isEmpty)
            let reviewed = try LocalCardStore.recordImportedReview(card.key, shown: before, rating: .good, at: date, in: url)
            let due = try XCTUnwrap(reviewed.schedule?.due)
            XCTAssertGreaterThan(due, date)
            XCTAssertFalse(reviewed.canReview(at: date))
            XCTAssertThrowsError(try LocalCardStore.recordImportedReview(card.key, shown: before, rating: .good, at: due, in: url))
            XCTAssertThrowsError(try LocalCardStore.recordImportedReview(card.key, shown: reviewed, rating: .hard, at: date, in: url))

            XCTAssertEqual(try LocalCardStore.load(from: url), snapshot)
            try LocalCardStore.importAnkiPackage(at: updated, into: url)
            try LocalCardStore.importAnkiPackage(at: updated, into: url)
            try LocalCardStore.replaceFromConfirmedPull(LearningSnapshot(), to: url)
            let reopened = try LocalCardStore.importedCard(card.key, from: url)
            XCTAssertEqual(reopened.schedule, reviewed.schedule)
            XCTAssertEqual(reopened.reviews.map(\.rating), [.good])
            XCTAssertEqual(reopened.reviews.map(\.reviewedAt), [date])
            XCTAssertEqual(try LocalCardStore.load(from: url), LearningSnapshot())
            let restored = try LocalCardStore.loadAnkiE1(from: url)
            XCTAssertEqual(restored.cards.first { $0.key == card.key }?.progress, raw)
            XCTAssertEqual(restored.notes.first?.body, "Обновлённая модель скорости реакции.")
            XCTAssertEqual(try LocalCardStore.importedCards(from: url).count, 2)
            let repeated = try LocalCardStore.recordImportedReview(card.key, shown: reopened, rating: .easy, at: due, in: url)
            XCTAssertGreaterThan(try XCTUnwrap(repeated.schedule?.due), due)
            XCTAssertEqual(try LocalCardStore.importedCard(card.key, from: url).reviews.map(\.rating), [.easy, .good])
        }
    }

    func testRealPackageAndMalformedInputDoNotOverwriteImportedCards() throws {
        try withStore { url in
            try LocalCardStore.importAnkiPackage(at: fixture("test1"), into: url)
            let original = try LocalCardStore.loadAnkiE1(from: url)
            XCTAssertEqual(original.notes.map(\.question), ["Что означает Km?", "Как влияет конкурентный ингибитор на Km?"])
            XCTAssertEqual(original.edges.map(\.type), ["requires", "required_for"])
            XCTAssertThrowsError(try LocalCardStore.importAnkiPackage(at: fixture("test4-type-change"), into: url))
            let broken = url.deletingLastPathComponent().appending(path: "broken.apkg")
            try Data("not a ZIP".utf8).write(to: broken)
            XCTAssertThrowsError(try LocalCardStore.importAnkiPackage(at: broken, into: url))
            XCTAssertEqual(try LocalCardStore.loadAnkiE1(from: url), original)
        }
    }

    func testCardHTMLHidesAnswerAndRetainsOnlyPassiveFormatting() throws {
        let content = ImportedCardContent(
            uid: "n-synthetic",
            title: "Карточка",
            question: #"<p onclick="ignored()">Вопрос <strong>Km</strong></p><script>script text</script>"#,
            answer: #"<a href="https://invalid.example/">Ответ</a><img src="file:///private/local"><pre> a   b</pre>"#,
            relations: [],
            mod: 1
        )
        let html = try ImportedCardHTML(content: content)
        XCTAssertTrue(html.question.contains("<p>Вопрос <strong>Km</strong></p>"))
        XCTAssertFalse(html.question.contains("Ответ"))
        XCTAssertFalse(html.question.contains("ignored()"))
        XCTAssertFalse(html.question.contains("script text"))
        XCTAssertTrue(html.revealed.contains("Ответ<pre> a   b</pre>"))
        XCTAssertFalse(html.revealed.contains("invalid.example"))
        XCTAssertFalse(html.revealed.contains("file:///"))
    }

    func testCardWithEmptyQuestionUsesEscapedTitleBeforeAndAfterReveal() throws {
        let content = ImportedCardContent(
            uid: "n-synthetic",
            title: "Выражение: &lt;x&gt; &amp; y",
            question: "",
            answer: "<p>Ответ <strong>здесь</strong></p>",
            relations: [],
            mod: 1
        )
        let html = try ImportedCardHTML(content: content)
        XCTAssertTrue(html.question.contains("<body>Выражение: &lt;x&gt; &amp; y</body>"))
        XCTAssertTrue(html.revealed.contains("<body>Выражение: &lt;x&gt; &amp; y<hr><p>Ответ <strong>здесь</strong></p></body>"))
    }

    func testRelationsAreVisibleAsLiteralTextOnlyAfterRevealWithEmptyAnswer() throws {
        let content = ImportedCardContent(
            uid: "n-synthetic",
            title: "Синтетика &lt;x&gt; &amp;lt;y&amp;gt;",
            question: "<p>Вопрос</p>",
            answer: "",
            relations: [
                .init(kind: .requires, targetUID: "n-first", note: "<img src='fixture'> &lt;tag&gt;"),
                .init(kind: .related, targetUID: "n-second", note: nil)
            ],
            mod: 1
        )
        let html = try ImportedCardHTML(content: content)
        XCTAssertEqual(html.title, "Синтетика <x> &lt;y&gt;")
        XCTAssertFalse(html.question.contains("n-first"))
        XCTAssertTrue(html.revealed.contains(
            "<li>requires → n-first: &lt;img src='fixture'&gt; &amp;lt;tag&amp;gt;</li><li>related → n-second</li>"
        ))
        XCTAssertFalse(html.revealed.contains("<img"))
    }

    // These three packages come from experiments/e1.py generate with genanki 0.13.1.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "apkg"))
    }

    private func withStore(_ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory.appending(path: "kanki.sqlite"))
    }
}
