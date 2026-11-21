import Foundation
import SwiftUI

/// Разделы и действия экрана «Обучение»: категории, очередь, локальные мутации.
extension LearningScreen {
    // MARK: - Секции

    /// Плавающая кнопка запуска повторения: due-очередь, а при пустой —
    /// досрочный сеанс по карточкам с будущим сроком.
    var reviewButton: some View {
        let selection = displayedReviewSelection
        let hasReviewableCards = !selection.cards.isEmpty
        return Button {
            startReview(in: .all)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(!localRead.isReadable || !hasReviewableCards ? Color.secondary : Color.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 56) }
        .accessibilityLabel(selection.isAhead ? "Досрочное повторение" : "Начать повторение")
        .accessibilityIdentifier("startReviewSession")
        .disabled(!localRead.isReadable || !hasReviewableCards)
        .animation(.easeInOut(duration: 0.2), value: hasReviewableCards)
    }

    @ViewBuilder
    var categoriesSection: some View {
        let named = categorySummaries.filter { $0.deck != nil }
        if !named.isEmpty {
            Section {
                ForEach(named, id: \.title) { summary in
                    CategorySummaryRow(
                        summary: summary,
                        availableDecks: availableDecks,
                        onStudy: { startReview(in: .category(summary.deck)) },
                        onRename: {
                            renameText = summary.title
                            renamingDeck = summary.deck
                        },
                        onDelete: { deckToDelete = summary },
                        onMove: { moveDeck(from: summary.deck, to: $0) }
                    )
                }
            } header: {
                Label("Категории", systemImage: "folder")
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
                        onStudy: { startReview(in: .category(nil)) },
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
                    cards: snapshot.cards,
                    schedules: snapshot.schedules,
                    clock: clock,
                    onOpen: { card in selectedCard = card },
                    onSetArchived: { card, archived in try setArchived(card, archived) },
                    onDelete: { card in try deleteCard(card) }
                )
            } label: {
                Label("Все карточки", systemImage: "rectangle.on.rectangle")
            }
        }
    }

    var statsSection: some View {
        let selection = displayedReviewSelection
        return Section {
            Text("К повторению: \(selection.isAhead ? 0 : selection.cards.count)")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dueCount")
            if selection.isAhead {
                Text("Доступно досрочно: \(selection.cards.count)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("aheadCount")
            }
            if newCardsCount > 0 {
                Text("Новых: \(newCardsCount)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("newCount")
            }
            Text("Оценок: \(log.count)")
                .foregroundStyle(.secondary)
            if let lastRating = log.lastRating {
                Text("Последняя оценка: \(lastRating.title)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Значения

    var addCardButton: some View {
        Menu {
            Button("Новая карточка") { isAddingCard = true }
            Button("Новый урок") { isCreatingLesson = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .background { FloatingCircleBackground(size: 44) }
        .accessibilityLabel("Добавить")
        .accessibilityIdentifier("addSessionCard")
        .disabled(!localRead.isReadable)
    }

    var log: SessionLog {
        SessionLog(reviews: snapshot.reviews)
    }

    private var displayedReviewSelection: ReviewQueue.Selection {
        ReviewQueue.select(snapshot.cards, in: .all, schedules: snapshot.schedules, at: clock)
    }

    var newCardsCount: Int {
        CardCategory.cards(snapshot.cards, archived: false)
            .filter { log.history(for: $0.id).isEmpty }
            .count
    }

    var categorySummaries: [CategorySummary] {
        CardCategory.summaries(of: snapshot, at: clock)
    }

    var availableDecks: [String] {
        Array(Set(snapshot.cards.compactMap(\.deck))).sorted()
    }

    private func startReview(in scope: ReviewQueue.Scope) {
        let selection = ReviewQueue.select(snapshot.cards, in: scope, schedules: snapshot.schedules, at: Date())
        guard !selection.cards.isEmpty else { return }

        reviewAttempt = ReviewAttempt(cards: selection.cards, isAhead: selection.isAhead)
    }

    func startLessonReview(_ lessonID: UUID) {
        guard let lesson = snapshot.lessons.first(where: { $0.id == lessonID }) else { return }
        let cards = snapshot.reviewCards(forLessonID: lessonID)
        guard !cards.isEmpty else { return }
        reviewAttempt = ReviewAttempt(cards: cards, isAhead: false, title: lesson.title)
    }

    // MARK: - Действия

    func record(_ card: SessionCard, rating: RecallRating) throws {
        var updated = snapshot
        try CardScheduling.record(card, rating: rating, in: &updated, at: Date())
        try apply(updated)
    }

    func reload() {
        do {
            let snapshot = try LocalCardStore.load()
            if snapshot != self.snapshot {
                pushGate.markChanged()
            }
            self.snapshot = snapshot
            localRead.didLoad()
            reviewAttempt = nil
            selectedCard = nil
            if let selectedLessonID, !snapshot.lessons.contains(where: { $0.id == selectedLessonID }) {
                self.selectedLessonID = nil
            }
        } catch {
            localRead.didFail("Не удалось прочитать сохранённые карточки: \(error.localizedDescription)")
            pushGate.markChanged()
            pushDebounceTask?.cancel()
            pushDebounceTask = nil
            reviewAttempt = nil
            selectedLessonID = nil
            selectedCard = nil
            isCreatingLesson = false
            isAddingCard = false
        }
    }

    /// Применяет изменённый снимок: сохраняет на диск и обновляет состояние экрана.
    func apply(_ updated: LearningSnapshot) throws {
        guard localRead.isReadable else { throw CocoaError(.fileReadCorruptFile) }
        var candidate = updated
        candidate.prepareForLocalMutation()
        try LocalCardStore.save(candidate)
        snapshot = candidate
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

    @discardableResult
    func changeDeck(of card: SessionCard, to newDeck: String?) throws -> SessionCard? {
        var updated = snapshot
        guard let index = updated.cards.firstIndex(where: { $0.id == card.id }) else { return nil }
        updated.cards[index].deck = CardCategory.trimmedDeck(newDeck)
        try apply(updated)
        return updated.cards[index]
    }

    /// Архивирует или возвращает карточку; открытая карточка получает новый флаг.
    func setArchived(_ card: SessionCard, _ archived: Bool) throws {
        var updated = snapshot
        guard updated.setArchived(archived, cardID: card.id) else { return }
        try apply(updated)
    }

    /// Сохраняет правку вопроса, ответа и категории; пустой ввод не применяется.
    @discardableResult
    func updateCard(
        _ card: SessionCard,
        question: String,
        answer: String,
        deck: String?
    ) throws -> SessionCard? {
        var updated = snapshot
        guard updated.updateCard(id: card.id, question: question, answer: answer, deck: deck) else {
            return nil
        }
        try apply(updated)
        return updated.cards.first { $0.id == card.id }
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
            operationAlert = "Не удалось удалить категорию: \(error.localizedDescription)"
        }
    }

    /// Перемещает все карточки категории в существующую (или в «Без категории»).
    /// Прямая переприсвойка `deck` — без записи rename-операции.
    func moveDeck(from source: String?, to target: String?) {
        var updated = snapshot
        let targetDeck = CardCategory.trimmedDeck(target)
        let movingIDs = Set(CardCategory.cards(updated.cards, inDeck: source, includingArchived: true).map(\.id))
        for index in updated.cards.indices where movingIDs.contains(updated.cards[index].id) {
            updated.cards[index].deck = targetDeck
        }
        do {
            try apply(updated)
        } catch {
            operationAlert = "Не удалось переместить карточки: \(error.localizedDescription)"
        }
    }
}
