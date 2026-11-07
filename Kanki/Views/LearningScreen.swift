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
    @State var isReviewing = false
    @AppStorage("serverRevision") var serverRevision = 0
    @AppStorage("serverHasUnsyncedChanges") var hasUnsyncedChanges = false
    @Environment(\.scenePhase) private var scenePhase
    @State var selectedCard: SessionCard?
    @State var isReviewingDeck = false
    @State var selectedDeck: String?
    @State var renamingDeck: String?
    @State var renameText = ""
    @State var renameError: String?
    @State var deckToDelete: CategorySummary?
    @State var pushTask: Task<Void, Never>?
    @State var syncError: String?
    @State var lastSyncFailed = false
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
        _loadError = State(initialValue: loadMessage)
    }

    var body: some View {
        List {
            if let loadError {
                Section("Не удалось открыть карточки") {
                    Text(loadError)
                    Button("Повторить чтение") { reload() }
                }
            } else if cards.isEmpty {
                emptyCardsSection
            } else {
                categoriesSection
                uncategorizedSection
                allCardsSection
                statsSection
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
            VStack(alignment: .trailing, spacing: 12) {
                addCardButton
                reviewButton
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $isAddingCard) {
            SessionCardFormScreen(availableDecks: availableDecks) { question, answer, deck in
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
                onUpdate: { question, answer, deck in
                    try updateCard(card, question: question, answer: answer, deck: deck)
                },
                onDelete: { try deleteCard(card) }
            )
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSessionScreen(
                cards: dueCards.isEmpty ? aheadCards : dueCards,
                title: dueCards.isEmpty ? "Досрочное повторение" : "Повторение"
            ) { card, rating in
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
            await reconcile()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reconcile() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kankiSnapshotReloaded)) { _ in
            reload()
        }
        .sheet(
            isPresented: $isChoosingCards,
            onDismiss: {
                if pendingSelectedExport {
                    pendingSelectedExport = false
                    isExporting = true
                }
            },
            content: {
                CardExportScreen(cards: cards) { selection in
                    exportDocument = CardExportDocument(
                        archive: CardExportArchive(snapshot: snapshot, selectedIDs: selection)
                    )
                    pendingSelectedExport = true
                }
            }
        )
        .fileExporter(isPresented: $isExporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "kanki-cards") { result in
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                exportError = error.localizedDescription
            }
        }
        .alert("Не удалось экспортировать", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Закрыть", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
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

struct FloatingCircleBackground: View {
    let size: CGFloat

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(.regularMaterial)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }
}
