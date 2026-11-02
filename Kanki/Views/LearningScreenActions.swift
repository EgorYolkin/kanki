import Foundation
import SwiftUI

extension LearningScreen {
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
        LearningSnapshot(cards: cards, reviews: log.reviews, schedules: schedules, deckRenames: deckRenames)
    }

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

    func moveDeck(from source: String?, to target: String?) {
        var updated = snapshot
        let targetDeck = CardCategory.trimmedDeck(target)
        let movingCards = CardCategory.cards(updated.cards, inDeck: source)
        let movingIDs = Set(movingCards.map(\.id))
        for index in updated.cards.indices where movingIDs.contains(updated.cards[index].id) {
            updated.cards[index].deck = targetDeck
        }
        do {
            try apply(updated)
        } catch {
            syncError = "Не удалось переместить карточки: \(error.localizedDescription)"
        }
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
        ReviewQueue.cards(CardCategory.cards(cards, inDeck: selectedDeck), schedules: schedules, at: clock)
    }

    var isSyncErrorPresented: Binding<Bool> {
        Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )
    }

    func serverClient() -> ServerClient? {
        guard let rawURL = UserDefaults.standard.string(forKey: "serverURL"),
              let configuration = ServerConfiguration(rawValue: rawURL)
        else {
            return nil
        }
        do {
            guard let stored = try ServerTokenStore.load() else { return nil }
            let token = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            return ServerClient(configuration: configuration, token: token)
        } catch {
            return nil
        }
    }

    /// Отправляет снимок на сервер после локального изменения с коротким debounce.
    func schedulePush() {
        guard let client = serverClient() else { return }
        let localSnapshot = snapshot
        let baseRevision = serverRevision
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            do {
                let result = try await client.push(
                    snapshot: localSnapshot,
                    baseRevision: baseRevision
                )
                serverRevision = result.revision
            } catch let error as ServerError {
                if case .conflict(let current) = error {
                    syncError = "Конфликт ревизий: на сервере \(current). Загрузите снимок в настройках."
                }
            } catch {
                // Сеть недоступна; ручная синхронизация покажет ошибку.
            }
        }
    }

    /// Первый запуск на пустом устройстве подтягивает серверный снимок.
    func pullIfLocalEmpty() async {
        guard cards.isEmpty, log.reviews.isEmpty, let client = serverClient() else { return }
        let localDecks = snapshot.localDeckCounts
        do {
            let remote = try await client.fetchSnapshot()
            guard let remoteSnapshot = remote.data else { return }
            // Потерянные при загрузке категории фиксируются на экране «Конфликты».
            ConflictLog.append(remoteSnapshot.lostCategoryMessages(localDecks: localDecks))
            try LocalCardStore.save(remoteSnapshot)
            serverRevision = remote.revision
            reload()
        } catch let error as ServerError {
            if case .conflict(let current) = error {
                syncError = "Конфликт ревизий: на сервере \(current)."
            }
        } catch {
            // Офлайн или сервер недоступен — локальные данные остаются.
        }
    }
}
