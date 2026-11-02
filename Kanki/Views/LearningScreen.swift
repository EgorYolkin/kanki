import Foundation
import SwiftUI

struct LearningScreen: View {
    @State var cards: [SessionCard]
    @State var log: SessionLog
    @State var schedules: [UUID: CardSchedule]
    @State var deckRenames: [DeckRename]
    @State var clock = Date()
    @State var loadError: String?
    @State var isAddingCard = false
    @State private var isReviewing = false
    @AppStorage("serverRevision") var serverRevision = 0
    @State var selectedCard: SessionCard?
    @State private var isReviewingDeck = false
    @State var selectedDeck: String?
    @State var renamingDeck: String?
    @State var renameText = ""
    @State var renameError: String?
    @State var deckToDelete: CategorySummary?
    @State var pushTask: Task<Void, Never>?
    @State var syncError: String?
    @State private var isChoosingCards = false
    @State private var exportDocument: CardExportDocument?
    @State private var isExporting = false
    @State private var pendingSelectedExport = false
    @State private var exportError: String?

    init() {
        var snapshot = LearningSnapshot()
        var loadMessage: String?
        do {
            snapshot = try LocalCardStore.load()
        } catch {
            loadMessage = "Не удалось прочитать сохранённые карточки: \(error.localizedDescription)"
        }
        _cards = State(initialValue: snapshot.cards)
        _log = State(initialValue: SessionLog(reviews: snapshot.reviews))
        _schedules = State(initialValue: snapshot.schedules)
        _deckRenames = State(initialValue: snapshot.deckRenames)
    }

    var body: some View {
        List {
        if let loadError {
            Section("Не удалось открыть карточки") {
                Text(loadError)
                Button("Повторить чтение") { reload() }
            }
        } else if cards.isEmpty {
            Section {
                SectionIntro(
                    symbol: "rectangle.stack",
                    title: "Карточек пока нет",
                    detail: "Добавьте карточку с вопросом и ответом кнопкой «плюс»."
                )
                .frame(maxWidth: .infinity)
            }
        } else {
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

            Section("Категории") {
                ForEach(categorySummaries.filter { $0.deck != nil }, id: \.title) { summary in
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

            if categorySummaries.contains(where: { $0.deck == nil }) {
                Section(CardCategory.noCategoryTitle) {
                    ForEach(categorySummaries.filter { $0.deck == nil }, id: \.title) { summary in
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
            }
        }
        }
    .contentMargins(.bottom, 90, for: .scrollContent)
    .navigationTitle("Обучение")
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Выбрать карточки") { isChoosingCards = true }
                Button("Экспортировать все") {
                    exportDocument = CardExportDocument(archive: CardExportArchive(snapshot: snapshot))
                    isExporting = true
                }
            } label: {
                Label("Экспорт", systemImage: "square.and.arrow.up")
            }
            .disabled(loadError != nil || cards.isEmpty)
            .accessibilityIdentifier("cardExportMenu")
        }
    }
    .task {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            clock = Date()
        }
    }
    .overlay(alignment: .bottomTrailing) {
        addCardButton
            .padding(.trailing, 20)
            .padding(.bottom, 20)
    }
    .sheet(isPresented: $isAddingCard) {
        AddSessionCardScreen(availableDecks: availableDecks) { question, answer, deck in
            try addCard(question: question, answer: answer, deck: deck)
        }
    }
    .sheet(item: $selectedCard) { card in
        SessionCardScreen(
            card: card,
            history: log.history(for: card.id),
            availableDecks: availableDecks,
            onReview: { rating in try record(card, rating: rating) },
            onChangeDeck: { newDeck in try changeDeck(of: card, to: newDeck) },
            onDelete: { try deleteCard(card) }
        )
    }
    .sheet(isPresented: $isReviewing) {
        ReviewSessionScreen(cards: dueCards) { card, rating in
            try record(card, rating: rating)
        }
    }
    .sheet(isPresented: $isReviewingDeck) {
        ReviewSessionScreen(cards: deckReviewCards) { card, rating in
            try record(card, rating: rating)
        }
    }
    .onAppear(perform: reload)
    .task {
        await pullIfLocalEmpty()
    }
    .onReceive(NotificationCenter.default.publisher(for: .kankiSnapshotReloaded)) { _ in
        reload()
    }
    .modifier(
        CardExportFlowModifier(
            isChoosingCards: $isChoosingCards,
            isExporting: $isExporting,
            pendingSelectedExport: $pendingSelectedExport,
            exportDocument: $exportDocument,
            exportError: $exportError,
            cards: cards
        ) { CardExportArchive(snapshot: snapshot, selectedIDs: $0) }
    )
    .alert("Синхронизация", isPresented: isSyncErrorPresented) {
        Button("OK", role: .cancel) {}
    } message: {
        Text(syncError ?? "")
    }
    .modifier(
        DeckManagementAlertsModifier(
            renamingDeck: $renamingDeck,
            renameText: $renameText,
            renameError: $renameError,
            deckToDelete: $deckToDelete,
            onRename: { renameDeck(from: $0, to: $1) },
            onDelete: { deleteDeck($0) }
        )
    )
    }

}
