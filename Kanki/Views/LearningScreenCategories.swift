import Foundation
import SwiftUI

/// Разделы и действия экрана «Обучение»: категории, очередь, локальные мутации.
extension LearningScreen {
    // MARK: - Секции

    @ViewBuilder
    var studySection: some View {
        Section {
            VStack(spacing: 6) {
                Button("Учить: \(dueCards.count) к повторению") {
                    isReviewing = true
                }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(loadError != nil || dueCards.isEmpty)
                .accessibilityIdentifier("startReviewSession")
                if newCardsCount > 0 {
                    Text("+\(newCardsCount) новых")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var categoriesSection: some View {
        let named = categorySummaries.filter { $0.deck != nil }
        if !named.isEmpty {
            Section("Категории") {
                ForEach(named, id: \.title) { summary in
                    CategorySummaryRow(
                        summary: summary,
                        availableDecks: availableDecks,
                        onStudy: {
                            selectedDeck = summary.deck
                            isReviewingDeck = true
                        },
                        onRename: {
                            renameText = summary.title
                            renamingDeck = summary.deck
                        },
                        onDelete: { deckToDelete = summary },
                        onMove: { moveDeck(from: summary.deck, to: $0) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    var uncategorizedSection: some View {
        let uncategorized = categorySummaries.filter { $0.deck == nil }
        if !uncategorized.isEmpty {
            Section(CardCategory.noCategoryTitle) {
                ForEach(uncategorized, id: \.title) { summary in
                    CategorySummaryRow(
                        summary: summary,
                        availableDecks: availableDecks,
                        onStudy: {
                            selectedDeck = nil
                            isReviewingDeck = true
                        },
                        onRename: {},
                        onDelete: {},
                        onMove: { moveDeck(from: nil, to: $0) }
                    )
                }
            }
        }
    }

    var allCardsSection: some View {
        Section {
            NavigationLink {
                AllCardsScreen(
                    cards: cards,
                    schedules: schedules,
                    clock: clock
                ) { card in
                    selectedCard = card
                }
            } label: {
                Label("Все карточки", systemImage: "rectangle.on.rectangle")
            }
        }
    }

    var statsSection: some View {
        Section {
            Text("К повторению: \(dueCards.count)")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dueCount")
            Text("Оценок: \(log.count)")
                .foregroundStyle(.secondary)
            if let lastRating = log.lastRating {
                Text("Последняя оценка: \(lastRating.title)")
                    .foregroundStyle(.secondary)
            }
            if let syncStatusText {
                Text(syncStatusText)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("syncStatus")
            }
        }
    }

    // MARK: - Значения

    var addCardButton: some View {
        Button {
            isAddingCard = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 44) }
        .accessibilityLabel("Добавить карточку")
        .accessibilityIdentifier("addSessionCard")
        .disabled(loadError != nil)
    }

    var snapshot: LearningSnapshot {
        LearningSnapshot(
            cards: cards,
            reviews: log.reviews,
            schedules: schedules,
            deckRenames: deckRenames
        )
    }

    var dueCards: [SessionCard] {
        ReviewQueue.cards(cards, schedules: schedules, at: clock)
    }

    var newCardsCount: Int {
        cards.filter { log.history(for: $0.id).isEmpty }.count
    }

    var categorySummaries: [CategorySummary] {
        CardCategory.summaries(of: snapshot, at: clock)
    }

    var availableDecks: [String] {
        Array(Set(cards.compactMap(\.deck))).sorted()
    }

    var deckReviewCards: [SessionCard] {
        ReviewQueue.cards(
            CardCategory.cards(cards, inDeck: selectedDeck),
            schedules: schedules,
            at: clock
        )
    }

    // MARK: - Действия

    func record(_ card: SessionCard, rating: RecallRating) throws {
        let previousSchedule = schedules[card.id]
        log.record(card, rating: rating)
        do {
            schedules[card.id] = try CardScheduling.nextReview(
                for: previousSchedule,
                rating: rating,
                at: Date()
            )
            try LocalCardStore.save(snapshot)
            schedulePush()
        } catch {
            log.discardLastRecord()
            schedules[card.id] = previousSchedule
            throw error
        }
    }

    func reload() {
        do {
            let snapshot = try LocalCardStore.load()
            cards = snapshot.cards
            log = SessionLog(reviews: snapshot.reviews)
            selectedCard = nil
            schedules = snapshot.schedules
            deckRenames = snapshot.deckRenames
            loadError = nil
        } catch {
            loadError = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
    }

    /// Применяет изменённый снимок: сохраняет на диск и обновляет состояние экрана.
    func apply(_ updated: LearningSnapshot) throws {
        try LocalCardStore.save(updated)
        cards = updated.cards
        log = SessionLog(reviews: updated.reviews)
        schedules = updated.schedules
        deckRenames = updated.deckRenames
        schedulePush()
    }

    func addCard(question: String, answer: String, deck: String?) throws {
        var updated = snapshot
        updated.cards.append(SessionCard(question: question, answer: answer, deck: deck))
        try apply(updated)
    }

    func deleteCard(_ card: SessionCard) throws {
        var updated = snapshot
        guard updated.removeCard(id: card.id) else { return }
        try apply(updated)
        selectedCard = nil
    }

    func changeDeck(of card: SessionCard, to newDeck: String?) throws {
        var updated = snapshot
        guard let index = updated.cards.firstIndex(where: { $0.id == card.id }) else { return }
        updated.cards[index].deck = CardCategory.trimmedDeck(newDeck)
        try apply(updated)
        selectedCard = updated.cards[index]
    }

    func renameDeck(from oldName: String, to newName: String) {
        var updated = snapshot
        do {
            try updated.renameDeck(from: oldName, to: newName)
            try apply(updated)
        } catch let error as CardCategoryError {
            renameError = error.message
        } catch {
            renameError = error.localizedDescription
        }
    }

    func deleteDeck(_ name: String) {
        var updated = snapshot
        updated.deleteDeck(name)
        do {
            try apply(updated)
        } catch {
            syncError = "Не удалось удалить категорию: \(error.localizedDescription)"
        }
    }

    /// Перемещает все карточки категории в существующую (или в «Без категории»).
    /// Прямая переприсвойка `deck` — без записи rename-операции.
    func moveDeck(from source: String?, to target: String?) {
        var updated = snapshot
        let targetDeck = CardCategory.trimmedDeck(target)
        let movingIDs = Set(CardCategory.cards(updated.cards, inDeck: source).map(\.id))
        for index in updated.cards.indices where movingIDs.contains(updated.cards[index].id) {
            updated.cards[index].deck = targetDeck
        }
        do {
            try apply(updated)
        } catch {
            syncError = "Не удалось переместить карточки: \(error.localizedDescription)"
        }
    }
}
