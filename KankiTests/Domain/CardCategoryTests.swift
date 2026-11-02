import XCTest
@testable import Kanki

final class CardCategoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func card(
        _ question: String,
        deck: String?,
        createdAt: Date = Date(timeIntervalSince1970: 100)
    ) -> SessionCard {
        SessionCard(question: question, answer: "Ответ", createdAt: createdAt, deck: deck)
    }

    private func schedule(
        for id: UUID,
        due: Date
    ) -> CardSchedule {
        CardSchedule(
            due: due,
            stability: 4.5,
            difficulty: 6,
            elapsedDays: 1,
            scheduledDays: 3,
            learningSteps: 0,
            reps: 1,
            lapses: 0,
            state: .review,
            lastReview: due
        )
    }

    // MARK: - trimmedDeck

    func testTrimmedDeckNormalizesWhitespaceAndEmpty() {
        XCTAssertEqual(CardCategory.trimmedDeck("  Математика "), "Математика")
        XCTAssertNil(CardCategory.trimmedDeck("   "))
        XCTAssertNil(CardCategory.trimmedDeck(nil))
        XCTAssertNil(CardCategory.trimmedDeck(""))
    }

    // MARK: - validationError

    func testValidationErrorReportsEachRule() {
        XCTAssertNotNil(CardCategory.validationError(for: "  ", existingDecks: []))
        XCTAssertNotNil(CardCategory.validationError(for: "Математика::Интегралы", existingDecks: []))
        XCTAssertNotNil(CardCategory.validationError(for: "Без категории", existingDecks: []))
        XCTAssertNotNil(CardCategory.validationError(for: "Математика", existingDecks: ["Математика"]))
        XCTAssertNil(CardCategory.validationError(for: "Математика", existingDecks: ["Физика"]))
    }

    // MARK: - cards(inDeck:)

    func testCardsInDeckIncludesSubdecksAndNilDeckIsSeparate() {
        let cards = [
            card("1", deck: "Математика"),
            card("2", deck: "Математика::Интегралы"),
            card("3", deck: "Математик"),
            card("4", deck: nil)
        ]

        XCTAssertEqual(CardCategory.cards(cards, inDeck: "Математика").map(\.question), ["1", "2"])
        XCTAssertEqual(CardCategory.cards(cards, inDeck: nil).map(\.question), ["4"])
    }

    // MARK: - summaries

    func testSummariesCountDueTotalNewAndSortWithUncategorizedLast() {
        let dueCard = card("due", deck: "Физика")
        let scheduledCard = card("later", deck: "Физика")
        let newCard = card("new", deck: "Физика")
        let plainCard = card("plain", deck: nil)
        let snapshot = LearningSnapshot(
            cards: [newCard, plainCard, scheduledCard, dueCard],
            reviews: [
                SessionReview(cardID: dueCard.id, rating: .good, reviewedAt: now),
                SessionReview(cardID: scheduledCard.id, rating: .good, reviewedAt: now)
            ],
            schedules: [
                dueCard.id: schedule(for: dueCard.id, due: now.addingTimeInterval(-10)),
                scheduledCard.id: schedule(for: scheduledCard.id, due: now.addingTimeInterval(1_000))
            ]
        )

        let summaries = CardCategory.summaries(of: snapshot, at: now)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].deck, "Физика")
        XCTAssertEqual(summaries[0].dueCount, 2)
        XCTAssertEqual(summaries[0].totalCount, 3)
        XCTAssertEqual(summaries[0].newCount, 1)
        XCTAssertEqual(summaries[1].deck, nil)
        XCTAssertEqual(summaries[1].totalCount, 1)
        XCTAssertEqual(summaries[1].newCount, 1)
    }

    func testSummariesHideEmptyUncategorizedWhenNamedDecksExist() {
        let snapshot = LearningSnapshot(cards: [card("1", deck: "Физика")])

        let summaries = CardCategory.summaries(of: snapshot, at: now)

        XCTAssertEqual(summaries.map(\.deck), ["Физика"])
    }

    func testSummariesKeepUncategorizedWhenItIsTheOnlySection() {
        let snapshot = LearningSnapshot(cards: [card("1", deck: nil)])

        let summaries = CardCategory.summaries(of: snapshot, at: now)

        XCTAssertEqual(summaries.map(\.deck), [nil])
        XCTAssertEqual(summaries.map(\.title), [CardCategory.noCategoryTitle])
    }

    // MARK: - renameDeck

    func testRenameDeckMovesDeckAndSubdecksAndRecordsOperation() throws {
        var snapshot = LearningSnapshot(cards: [
            card("1", deck: "Математика"),
            card("2", deck: "Математика::Интегралы"),
            card("3", deck: "Физика")
        ])

        try snapshot.renameDeck(from: "Математика", to: "Алгебра")

        XCTAssertEqual(snapshot.cards.map(\.deck), ["Алгебра", "Алгебра::Интегралы", "Физика"])
        XCTAssertEqual(snapshot.deckRenames, [DeckRename(from: "Математика", to: "Алгебра")])
    }

    func testRenameDeckRejectsInvalidAndDuplicateNames() throws {
        var snapshot = LearningSnapshot(cards: [card("1", deck: "Математика"), card("2", deck: "Физика")])

        XCTAssertThrowsError(try snapshot.renameDeck(from: "Математика", to: "Физика"))
        XCTAssertThrowsError(try snapshot.renameDeck(from: "Математика", to: "Математика::X"))
        XCTAssertThrowsError(try snapshot.renameDeck(from: "Не существует", to: "Новое"))
        XCTAssertEqual(snapshot.cards.map(\.deck), ["Математика", "Физика"])
        XCTAssertTrue(snapshot.deckRenames.isEmpty)
    }

    // MARK: - deleteDeck

    func testDeleteDeckMovesCardsToNoCategoryAndPromotesSubdecks() {
        var snapshot = LearningSnapshot(cards: [
            card("1", deck: "Математика"),
            card("2", deck: "Математика::Интегралы")
        ])

        snapshot.deleteDeck("Математика")

        XCTAssertEqual(snapshot.cards.map(\.deck), [nil, "Интегралы"])
    }

    // MARK: - applyingRenames

    func testApplyingRenamesRebuildsHierarchyWithoutLosingSubdecks() {
        let snapshot = LearningSnapshot(cards: [
            card("1", deck: "Математика"),
            card("2", deck: "Математика::Интегралы"),
            card("3", deck: "Физика")
        ])

        let renamed = snapshot.applyingRenames([DeckRename(from: "Математика", to: "Точные науки")])

        XCTAssertEqual(renamed.cards.map(\.deck), ["Точные науки", "Точные науки::Интегралы", "Физика"])
    }

    // MARK: - lostCategoryMessages

    func testLostCategoryMessagesIgnoreRenamedAndSubdeckSurvivors() {
        let remote = LearningSnapshot(
            cards: [card("1", deck: "Алгебра")],
            deckRenames: [DeckRename(from: "Математика", to: "Алгебра")]
        )

        let messages = remote.lostCategoryMessages(localDecks: [
            "Математика": 2,
            "Физика": 1,
            "Химия::Органика": 3
        ])

        XCTAssertEqual(messages, [
            "Карточка потеряла категорию «Физика» (удалена на другом устройстве)",
            "3 карточек потеряли категорию «Химия::Органика» (удалена на другом устройстве)"
        ])
    }

    func testLostCategoryMessagesEmptyWhenNothingLost() {
        let remote = LearningSnapshot(cards: [card("1", deck: "Математика")])

        XCTAssertTrue(remote.lostCategoryMessages(localDecks: ["Математика": 1]).isEmpty)
        XCTAssertTrue(remote.lostCategoryMessages(localDecks: [:]).isEmpty)
    }

    // MARK: - localDeckCounts

    func testLocalDeckCountsSkipUncategorized() {
        let snapshot = LearningSnapshot(cards: [
            card("1", deck: "Математика"),
            card("2", deck: "Математика"),
            card("3", deck: nil)
        ])

        XCTAssertEqual(snapshot.localDeckCounts, ["Математика": 2])
    }
}
